---
name: react
description: Write idiomatic, production-grade React 19+ with TypeScript. Self-contained — all rules inline, no reference files. Use when editing React DOM code: .tsx or .jsx files with React components, hooks, or their tests; apps built on Next.js, React Router, or TanStack Start; a React app built with Vite, including its build, lint, TypeScript, and package config; or when asked to design, generate, or review React code. Not for React Native. Covers the Rules of React, components, hooks and effects, state, data fetching, forms and actions, Server Components, routing, TypeScript, styling, accessibility, errors and Suspense, performance, security, testing, tooling, project layout, and version-gated modern APIs.
---

# Skill: react

Write React that a senior frontend engineer would ship to production. This file is self-contained: every rule is stated inline — reconstruct each shape with your own knowledge of idiomatic React, and get the error-prone lines the rules call out right. Rules target React DOM; a React Native task does not use them.

> **IMPORTANT: These rules are MANDATORY and MUST be strictly followed without exception.**

## Non-negotiables (every .tsx/.jsx file)

- TypeScript (`.tsx`) for new code; in a JavaScript project keep `.js`/`.jsx` with JSDoc types and never convert files unasked. Function components with hooks; a class component only as an error boundary, and prefer `react-error-boundary` for that.
- Output passes the project's formatter and the ESLint config in Tooling & CI (`eslint-plugin-react-hooks` v7+, compiler rules on) — run them before finishing; no unused imports or variables.
- Match the installed `react`, framework, and TypeScript versions. Never emit an API newer than installed unless bumping is part of the task (see the version list at the end).
- Obey the Rules of React (next section): the compiler and the lint rules assume them, so a violation is a bug even when it renders today.
- Secrets and server-only code never reach a `'use client'` module graph; every client input is validated on the server.
- Platform first: check whether the browser, React, or the framework covers it (`fetch`, `Intl`, `URL`, `structuredClone`, `<dialog>`, `popover`, CSS) before adding a dependency.
- New or changed non-trivial logic ships with a test in the same change.

## Rules of React (the compiler and linter assume these)

- Components and hooks are pure and idempotent: same props, state, and context → same output; no side effects during render (no mutation of outer scope, no writes or I/O beyond the awaited reads of an async Server Component, no `Date.now()`/`Math.random()` unless captured into state). React renders twice in StrictMode and may discard a render.
- Props, state, context values, hook arguments and returns, and anything already passed to JSX are immutable: build new values (`{...s, x}`, `.map`, `.filter`, `.toSorted()` on an ES2023 lib or `[...a].sort()`), never `push`/`sort`/assign in place.
- Hooks are called at the top level only, before any early return, never in loops, conditions, or nested functions, and only from components or other hooks (named `useX`). `use` is the one exception: it may be called in loops, in conditions, and after early returns, but never inside `try/catch` — an error boundary handles a rejected promise.
- Never call a component as a function (`Comp()`) — render `<Comp />`; never pass hooks around as values.
- Never read or write `ref.current` during render (lint `refs`); refs hold values React must not react to.
- Never define a component inside another component (lint `static-components`) — it remounts every render.

## Components

- One primary component per file, exported PascalCase from a kebab-case file (`user-profile.tsx` → `UserProfile`); the parts of a compound component and a framework route module's extra exports (`loader`, `ErrorBoundary`, `HydrateFallback`) share the file; colocate its test, stories, styles, and private subcomponents.
- Props: a named `type`/`interface` per component, destructured in the signature with defaults (`defaultProps` is gone for function components); `children: ReactNode`; model mutually dependent props as a discriminated union, not optional flags that only make sense together.
- No boolean mode props that fork behavior through the component: split components or accept slots; a `variant` union selects presentation through a table or `cva`, never branches logic.
- Composition over configuration: pass `children` and slots (`header`, `actions`) and build compound components as named exports from one `'use client'` module (`Tabs`, `TabsList`, `TabsTrigger`), never dot-notation sub-components (`Tabs.List` throws when a Server Component renders it); composition or context instead of prop drilling past two levels.
- `ref` is a regular prop (19+): `function Input({ ref, ...props }: ComponentProps<'input'>)`; `forwardRef` only for pre-19 code. `useImperativeHandle` only to expose a minimal imperative API (focus, scroll).
- Wrappers of DOM elements spread rest props onto the element, typed with `ComponentProps<'button'>` or `ComponentProps<typeof Base>` (both include `ref` in 19; `ComponentPropsWithoutRef` only when deliberately not forwarding it); merge `className` and event handlers instead of overriding them.
- Controlled or uncontrolled, never both: `value` without `onChange` is a bug unless the input is `readOnly`, and an input must not switch between `undefined` and a value.
- Lists: a stable `key` from data identity, never the array index for lists that reorder, filter, or insert; use `key` deliberately to reset a component's state. `&&` leaks `0`/`NaN` into the output — guard with a boolean (`count > 0 && …`) or a ternary.
- Guard clauses in render after the hooks: return early for loading, error, and empty states; no nested ternaries in JSX — compute a variable or extract a component; switch exhaustively on a `status` union; a map of variant → component beats an if-chain.
- Event handlers are `onX` in props and `handleX` inside; no handlers that only forward (`onClick={() => onClick()}`).
- Derive, don't store: anything computable from props or state is computed in render (the compiler memoizes); no state mirroring props (reset with `key` or lift state), no effects that copy one state into another.
- With the React Compiler on, don't hand-write `memo`/`useMemo`/`useCallback` for performance; the one escape hatch and the no-compiler rules are in Performance.
- Text: `Intl.*` with an explicit locale and `timeZone` (server and browser defaults differ and break hydration), or format in a Client Component; messages through the project's i18n library with ICU plurals; never concatenate translated fragments.

## Hooks & effects

- Effects synchronize with external systems (subscriptions, DOM APIs, timers, non-React widgets); they are not lifecycle hooks: no fetch chains (Data fetching), no event logic (do it in the handler), no "when X changes set Y" (derive it, or set it where X changes) — lint `set-state-in-effect` flags the last.
- An effect that sets something up returns a cleanup that undoes exactly that (unsubscribe, `clearTimeout`, `AbortController.abort()`); every effect must survive mount → cleanup → mount (StrictMode, `<Activity>`, Fast Refresh).
- Dependency arrays are complete (`exhaustive-deps`) — never silence the rule; fix the cause: move the function inside the effect, read latest values through `useEffectEvent`, or keep non-reactive values in a ref.
- `useEffectEvent` (19.2+) is called at the top level like any hook; the function it returns is called only from effects or other effect events — never listed in deps, passed to children, or called in render or handlers; it is not a dependency-skipping tool.
- `useLayoutEffect` only for measurements and scroll positions that must apply before paint; `useInsertionEffect` only for CSS-in-JS libraries.
- Custom hooks encapsulate one concern and return a small named object or tuple; they are the unit of reuse for stateful logic — not HOCs or render props.
- `useSyncExternalStore` for anything outside React (a store, `matchMedia`, `localStorage`, `navigator.onLine`) with a `getServerSnapshot` for SSR; never mirror it with `useEffect` + `setState`.
- `useId` for element ids and ARIA linkage; never `Math.random()` or counters (hydration mismatch).
- `useState(() => compute())` for expensive initial values; functional updates (`setN(n => n + 1)`) when the next value depends on the previous; a setter is a request for the next render, not an assignment.
- `useReducer` when transitions touch several fields or are event-driven; keep the reducer pure and switch exhaustively on `action.type`.

## State

- Keep state minimal and local; lift only to the lowest common ancestor.
- Three kinds, three tools: server data → TanStack Query (or framework loaders / Server Components); client UI state → `useState`/`useReducer`, Zustand or Jotai when shared across the tree; URL state → router search params (shareable, back-button-aware). Never copy server data into a client store (Zustand, Jotai, local state) — the Query cache is the server-data store, not a second copy.
- Context for low-frequency, wide-reach values (theme, session, locale, a store instance): split value and dispatch contexts, render `<Ctx value={…}>` and read with `use(Ctx)` (both 19+). Not for high-frequency updates (every consumer re-renders) — use a store with selectors.
- Zustand: one store per domain, selectors (`useStore(s => s.x)`, `useShallow` for objects), actions defined inside the store; Jotai for many independent atoms; Redux Toolkit only in codebases that already use Redux.
- Make illegal states unrepresentable: a discriminated union (`{ status: 'idle' } | { status: 'error'; error: E } | …`), not three booleans.
- Immutable updates; `immer`/`useImmer` or Zustand's `immer` middleware for deep updates.
- Form state belongs to the form (Forms & actions), not a global store; ephemeral UI state (open menus) stays local.

## Data fetching

- Fetch on the server when you can: Server Components or route loaders fetch and pass data down; Client Components receive data or a promise (`use(promise)` under `<Suspense>`).
- Client fetching goes through TanStack Query v5: `queryOptions()` factories per resource (shared keys and types); every value the `queryFn` reads is in the `queryKey` (lint `@tanstack/eslint-plugin-query`); a `queryFn` throws on `!response.ok` because `fetch` doesn't; `useQuery`/`useSuspenseQuery`, `staleTime` set deliberately, `select` to narrow; mutations invalidate on settle, and an optimistic `setQueryData` cancels in-flight queries and snapshots in `onMutate`, rolls back in `onError`, invalidates in `onSettled`. Never `useEffect` + `fetch` + `useState` — no cancellation, no cache, race conditions, waterfalls.
- One `QueryClient` per request on the server (a module-level client shares one user's cache with every request) and one stable instance in the browser.
- Avoid waterfalls: start requests in parallel (`Promise.all`, parallel queries, `prefetchQuery` in loaders), hoist fetching to the route or boundary, `preload`/`preconnect` critical resources.
- A promise given to `use` must be stable: created on the server, in a loader, or cached (`cache()` in RSC, the Query cache); a promise created during client render suspends forever.
- Pass an `AbortSignal` (`signal` from Query, `cacheSignal()` in RSC 19.2+) to `fetch`; treat the network as unreliable: typed errors, retries only for idempotent requests.
- Parse responses at the boundary (Zod 4 / Valibot `safeParse`) into domain types; components never see raw JSON.

## Forms & actions (19+)

- `<form action={fn}>` with Actions: `useActionState(action, initialState)` returns `[state, dispatch, isPending]`, the action is `(prevState, formData) => nextState`, and `dispatch` runs only inside an `action` prop or `startTransition`; `useFormStatus()` in a child component rendered inside the form; `useOptimistic` shows its value only while the action is pending — afterwards React renders the real state, so persist the change on success; on failure the UI reverts by itself, return `{ error }` to show a message (a throw cancels queued actions and reaches the error boundary).
- Non-form mutations run inside the `startTransition` returned by `useTransition` (`startTransition(async () => { await save(); })`) so `isPending` tracks them and a thrown error reaches the nearest error boundary; a state update after an `await` inside a transition needs its own `startTransition`.
- `'use server'` modules export only async functions and every export is a public POST endpoint — one action per file, helpers in a plain module; inline `'use server'` only in server-side files, never in a Client Component, which imports from a `'use server'` module; an inline action takes its inputs as arguments and never closes over a secret, a database row, or an authorization result (closed-over values travel to the client). Authorization, validation, and return rules: Security.
- Call `redirect()`/`notFound()` outside `try/catch` — they throw.
- `<form action>` resets uncontrolled fields when the action succeeds (`useActionState` has no reset); for complex client-validated forms (many fields, live validation, field arrays) use `react-hook-form` + `@hookform/resolvers` (Zod 4) — with the compiler on, `useWatch` not `watch` (lint `incompatible-library`) — and dispatch the action from `handleSubmit` inside `startTransition`.
- One schema, two runs: the same Zod schema validates in the browser for UX and on the server for trust; the server run is authoritative.
- Native semantics: `<label htmlFor>`, `type="email"`, `required`, `autoComplete`, and a `name` on every control so the form works without JS and `FormData` carries it; link validation messages with `aria-invalid` + `aria-describedby` (ids from `useId`) or a `role="alert"` summary.

## Server Components & server functions (RSC frameworks)

- Server Components are the default: they may be `async` and read databases, files, and secrets; they support `use`, `useId`, `useMemo`, and `useCallback` but no state, effects, context reads, browser APIs, or event handlers. Client Components are never `async` — pass them a promise and `use` it under `<Suspense>`.
- `'use client'` marks a boundary, not "runs only in the browser": the module and everything it imports joins the client bundle and still pre-renders on the server. Put it on leaves (interactive widgets), not layouts; pass Server Components into Client Components as `children` or props instead of importing them.
- Props crossing the boundary must be serializable: primitives, plain objects and arrays, `Date`, `Map`/`Set`, promises, JSX; no functions (except Server Functions), classes, or class instances. Pass a promise and `use` it in the client to stream.
- `import 'server-only'` in data and secret modules (build error when a client module imports them), `import 'client-only'` for browser-only modules. Only the data-access layer reads `process.env`; `NEXT_PUBLIC_`/`VITE_` prefixed variables are public.
- Data-access layer: server-only functions that authorize and return DTOs with only the fields the UI needs; never pass a raw database row or user object to a Client Component (the taint APIs are experimental and only a backstop).
- `cache()` dedupes per-request reads across the tree (`getCurrentUser`); never keep request or user data in the module scope of a server module — it is shared across requests; `cacheSignal()` (19.2+) aborts work when the cache lifetime ends.
- Context is created in a `'use client'` module; 19.3+ lets a Server Component render `<Ctx value={…}>` directly, earlier versions need a client provider component.
- `browser()` (19.3+, `react-dom`): `use(browser())` in a Client Component under `<Suspense>` (without a boundary the server render fails) skips server rendering of a component that needs `window` or `localStorage` — replaces `typeof window` checks and "mounted" effects; before 19.3 use `useSyncExternalStore` with a server snapshot.
- Streaming: wrap slow server subtrees in `<Suspense>` so the shell streams first; fallbacks are sized like the content to avoid layout shift.

## Routing & frameworks

- Pick by need: Next.js 16 App Router for the broadest ecosystem and RSC; React Router 8 framework mode (loaders, actions, middleware; self-hosts on Node; ESM-only; imports from `react-router` and `react-router/dom`); TanStack Start 1.0 (TanStack Router's typed routes and search params, plus `createServerFn` for server functions); a Vite SPA only when SEO and SSR don't matter (internal tools). Never scaffold with Create React App.
- Next.js 16: `params`, `searchParams`, `cookies()`, `headers()` are awaited; `proxy.ts` replaces `middleware.ts` (Node runtime only); `loading.tsx`/`error.tsx`/`not-found.tsx` per segment; `route.ts` for HTTP APIs; `revalidateTag(tag, 'max')` (the profile argument is required) for stale-while-revalidate, `updateTag(tag)` in Server Actions for read-your-writes; `next lint` is gone — run ESLint with `eslint-config-next`.
- Cache Components (`cacheComponents: true`, 16.0+; `partialPrefetching: true`, 16.3+, requires it; new 16.4 apps enable the model and 17 makes it the default): everything renders at request time unless marked `'use cache'` with `cacheLife()`/`cacheTag()`; read `params`, `searchParams`, `cookies()`, `headers()` inside `<Suspense>` and `useSearchParams` always under one, or the static shell can't prerender; 16.4+ adds `export const ensureStatic = 'navigation'` (the only level that fails the build on dynamic content — `'shell'`/`'prefetch'` only move the stage) and `await navigation()`/`await prefetch()` from `next/cache` (they throw without Cache Components or inside a Client Component).
- React Router 8: loaders and actions per route module with typed `Route.LoaderArgs`, middleware always on (`context` is a `RouterContextProvider`: `context.get`/`set` with `createContext()` keys), `meta({ loaderData })`; requires React 19.2.7+, Node 22.22+, Vite 7+; RSC mode is still unstable.
- Routes are the unit of code splitting (`lazy()` + `<Suspense>` or framework route modules); internal navigation uses the framework's `<Link>`, a plain `<a>` only for external links and downloads.
- URL is state: filters, pagination, and the selected tab live in search params with typed parsing (TanStack `validateSearch`, `nuqs`, or a Zod schema), not in `useState`.
- Wrap navigation in transitions (`startTransition` or the router's API) so pending UI shows and `<ViewTransition>` (19.3+) animates.

## TypeScript

- `strict` plus `noUncheckedIndexedAccess`; `"jsx": "react-jsx"`, `"module": "esnext"` (or `"preserve"`), `"moduleResolution": "bundler"`, `"verbatimModuleSyntax": true`, `"noEmit": true` (the bundler emits), `"erasableSyntaxOnly": true` (TS 5.8+; no enums, namespaces, or parameter properties — string-literal unions instead). TypeScript 6+ defaults `strict` on, `module` to `esnext`, `types` to `[]` — list globals explicitly (`"types": ["vite/client", "node"]`) — and `rootDir` to `./`; 7 turns the 6.0 deprecations into errors (`baseUrl`, `moduleResolution: node` — make `paths` relative to the project).
- Types: `ReactNode` for renderable children, `ReactElement` only when an element is required; no `React.FC` (no implicit children, blocks generics); `ComponentProps<'x'>` / `ComponentProps<typeof X>` to inherit; `Ref<T>`/`RefObject<T>` for refs; event types from `react` (`MouseEvent<HTMLButtonElement>`); `React.JSX.Element` — the global `JSX` namespace is gone in the 19 types.
- `useRef` requires an argument in the 19 types and `useRef<T>(null)` returns `RefObject<T | null>`; ref callbacks use a block body (an implicit return is now a cleanup function); `useReducer(reducer, initialState)` with inference, not `useReducer<Reducer<…>>`.
- Discriminated unions for props and state; `satisfies` for config objects; `as const` for literal tuples; no `any` — `unknown` at boundaries, then parse; no non-null assertions on refs — handle `null`.
- Generic components (`function List<T extends { id: string }>({ items, render }: ListProps<T>)`) for reusable data-driven UI.
- `import type` for types; default exports only where the framework requires them (route modules, `lazy()`), named exports elsewhere.
- typescript-eslint has no TypeScript 7 API (its peer range stops below 6.1): with TS 7, alias `typescript` to `npm:@typescript/typescript6` for the linter and add `@typescript/native` → `npm:typescript@^7` for `tsc`; drop the alias once typescript-eslint's peer range includes 7.

## Documentation

- JSDoc on an exported component, hook, or prop only when its name can't carry the contract (units, accepted ranges, nullability, when a callback fires, server-only or client-only); it shows in the editor and in Storybook docgen. A comment that restates the name is noise — rename instead.
- Every other comment says *why*: intent, invariant, workaround (with the issue link).
- Stories are runnable docs: one story per meaningful state of a shared component.

## Styling

- Zero-runtime first: Tailwind v4 (`@import "tailwindcss"`, `@theme` tokens in CSS, no `tailwind.config.js`), CSS Modules, or vanilla-extract/Panda — they work in Server Components and ship no runtime. Runtime CSS-in-JS (styled-components, Emotion) only inside `'use client'` with a style registry; avoid in new code.
- Compose class names with `clsx` + `tailwind-merge` (`cn()`); define variants with `cva`/`tailwind-variants`, not ad-hoc conditionals; never build Tailwind classes from strings (`bg-${color}-500` is never generated) — map to full class names.
- Design tokens as CSS custom properties; dark mode via `prefers-color-scheme` or a `data-theme` attribute; inline `style` only for truly dynamic values (transforms, positions).
- Layout with modern CSS (grid, flex, container queries, `:has()`, logical properties); don't measure with JS what CSS can lay out.
- 19+ hoists `<link rel="stylesheet" href precedence="…">` (deduped by `href`; Suspense waits for it), `<title>`, and `<meta>` rendered anywhere in the tree into `<head>`; render one `<title>` at a time — several are all placed and browser behavior is undefined; a framework's metadata API still wins for routes.

## Accessibility

- Semantic HTML first: `<button>` for actions, `<a href>` for navigation (never `<div onClick>`, `href="#"`, or `javascript:`), headings in order, landmarks, `<ul>`/`<table>` for lists and tables, `<dialog>` and `popover` where supported.
- Every control has an accessible name (`<label>`, `aria-label`, `aria-labelledby`); images have `alt` (empty when decorative); icon buttons get `aria-label`.
- Keyboard: everything reachable and operable, visible focus, no positive `tabIndex`; move focus into dialogs and to the new heading on route change, restore it on close.
- ARIA only when no native element fits; complex widgets (combobox, menu, dialog, date picker) come from headless primitives (Base UI via `@base-ui/react`, React Aria Components, or Radix), never hand-rolled.
- Announce async changes with `aria-live="polite"` / `role="status"`; gate animations and view transitions on `prefers-reduced-motion`.
- Lint with `eslint-plugin-jsx-a11y`; test with `getByRole` queries (they fail when semantics are missing) and axe: `@axe-core/playwright` end-to-end, `axe-core`'s `axe.run(container)` in component tests (`vitest-axe` is unmaintained).

## Errors & Suspense

- Error boundaries at deliberate isolation points (route, widget, list item), not one at the root: `react-error-boundary`'s `<ErrorBoundary fallbackRender onError onReset resetKeys>` with a retry action in the fallback; `useErrorBoundary()` returns `showBoundary` for errors from handlers and promises. Boundaries do not catch errors thrown in event handlers, in promises, or during SSR; in 19 they do catch an error thrown inside a `useTransition` action. With `useSuspenseQuery`, wire `useQueryErrorResetBoundary().reset` to `onReset` or the fallback re-throws the cached error.
- `createRoot`/`hydrateRoot` options `onUncaughtError`, `onCaughtError`, `onRecoverableError` report to the error tracker (19+ no longer rethrows). Fix hydration mismatches at the cause (non-deterministic render); `suppressHydrationWarning` only on a single known-different text node such as a timestamp.
- Pair every `<Suspense>` with an error boundary: `use` and `useSuspenseQuery` throw to the nearest one. Boundaries wrap the subtree that should show a fallback together (streaming granularity); fallbacks are visually stable.
- Expected failures are values, not exceptions: actions return `{ error }` (framework `redirect()`/`notFound()` still throw — call them outside `try/catch`), queries expose `error`, forms show field errors; throw for bugs and unrecoverable states.
- Never swallow errors: a `catch` that only logs and continues is a bug unless the operation is optional by design; report through one tracker with context, no `console.log` in shipped code.

## Performance (measure first — React DevTools Profiler, React Performance Tracks (19.2+) in Chrome, Lighthouse and `web-vitals`; INP is the interaction metric)

- React Compiler on by default in new projects (`babel-plugin-react-compiler`, pinned to an exact version): Vite 8 → `import react, { reactCompilerPreset } from '@vitejs/plugin-react'` passed to `@rolldown/plugin-babel` as `babel({ presets: [reactCompilerPreset()] })` (plugin-react v6 also has an experimental native `react({ compiler: true })`); Next.js → `reactCompiler: true`; React 17/18 → the `target` option plus `react-compiler-runtime`. Adopt incrementally (`compilationMode: 'annotation'` + `"use memo"`); `"use no memo"` opts a broken component out while you fix the rule violation — the compiler skips that component, but the lint error still fails the lint step.
- `useMemo`/`useCallback` remain only as the compiler's documented escape hatch: a value used as an effect dependency that must keep its identity. Without the compiler: `memo` a component only when it re-renders often with equal props and profiling shows the cost; `useMemo` for expensive derivations or referentially stable deps; `useCallback` only for handlers passed to memoized children or effects.
- Keep urgent updates responsive: `useTransition`/`startTransition` for non-urgent state (navigation, filtering large lists), `useDeferredValue` (19+ `initialValue` for the first render) for expensive UI driven by an input, so typing never waits on rendering.
- Code-split by heavy feature on top of route splitting (`lazy(() => import('./Chart'))` under `<Suspense>`); dynamic-import heavy libraries at interaction time; inspect bundles with the framework analyzer or `rollup-plugin-visualizer`; no catch-all barrels (`export *` of a whole UI kit or `lib/`) — a feature's `index.ts` exports only its public API.
- Virtualize long lists (`@tanstack/react-virtual`); paginate or infinite-query server data.
- Images and fonts: explicit `width`/`height`, `loading="lazy"` below the fold, `fetchPriority="high"` on the LCP image, modern formats, the framework `<Image>`; `preload`/`preinit`/`preconnect` from `react-dom` (19+) for critical resources; self-hosted fonts with `font-display`.
- No layout thrash: batch DOM reads and writes, measure in `useLayoutEffect`, observe with `ResizeObserver`/`IntersectionObserver` (Fragment refs 19.3+: `observeUsing` for a group of children).
- `<Activity mode="hidden">` (19.2+) keeps state and DOM of hidden tabs and pre-renders likely-next content (prefetches data read through any Suspense-enabled source such as `use`, not effect fetches); effects are unmounted while hidden; pause media in a `useLayoutEffect` cleanup.
- Hydrate less: Server Components for static and data-heavy UI, `'use client'` at leaves; Suspense and Activity boundaries enable selective hydration.
- A context value built as a new object each render re-renders every consumer — memoize it (the compiler does; otherwise `useMemo`) or move it to a store with selectors.

## Security

- Keep React's escaping: no `dangerouslySetInnerHTML` without sanitizing at render time (`DOMPurify.sanitize`, `rehype-sanitize` for Markdown) through one shared component. React rewrites `javascript:` URLs in `href`/`src` to a blocked one (since 16.9), so still allowlist schemes (`http(s):`, `mailto:`) for user-supplied links; `target="_blank"` gets `rel="noopener noreferrer"`.
- CSP: nonce-based `script-src 'nonce-…' 'strict-dynamic'`, no `unsafe-inline`/`unsafe-eval`; pass `nonce` to `<script>`/`<style>` and `preinit`; 19.3+ passes Trusted Types values through, so `require-trusted-types-for 'script'` works.
- Server boundary: Server Functions and route handlers authenticate and authorize per call (a page-level check or a Proxy matcher doesn't cover them), verify resource ownership (IDOR), validate inputs with a schema, rate-limit expensive ones, and return DTOs — never raw rows, never internals in thrown errors.
- Secrets live in server env only (the public prefixes are listed under Server Components); never ship API keys, never log tokens or PII.
- Auth tokens in `httpOnly`, `Secure`, `SameSite` cookies, not `localStorage`; mutations are POST with same-origin checks (Next.js compares `Origin` to `Host`; set `experimental.serverActions.allowedOrigins` when a proxy doesn't forward the public host in `x-forwarded-host`).
- RSC supply chain: keep `react-server-dom-*` and the framework on the latest patch of their line — as of 2026-10-23 that is 19.3.1 / 19.2.9 / 19.1.10 / 19.0.9 and Next.js 16.4.1 / 15.5.28 (React2Shell, CVE-2025-55182, and the follow-ups through GHSA-xqc2-xf4c-x3h3) — and treat any open advisory on them as blocking; `pnpm audit`/`npm audit` on a frozen lockfile in CI; review and pin new dependencies, keep them few.
- Untrusted embeds use `<iframe sandbox>`; `postMessage` with an explicit `targetOrigin` and an origin check on receive.
- Data inlined into `<script>` or JSON islands escapes `<` (`JSON.stringify(x).replace(/</g, '\\u003c')`).

## Testing

- Vitest 4+ with `@testing-library/react`, `@testing-library/user-event`, and `@testing-library/jest-dom/vitest`; `jsdom` for logic-heavy components, Vitest Browser Mode (`@vitest/browser-playwright`, `vitest-browser-react`, `page.getByRole` locators, `await expect.element(…)`) for layout- and interaction-sensitive ones; Playwright for end-to-end.
- Test as a user: query by role, label, or text (`getByRole` first, `getByTestId` last), interact with `userEvent.setup()` (not `fireEvent`), assert visible outcomes; `findBy*` for async UI, never `waitFor` wrapping side effects or arbitrary sleeps; no snapshots of whole trees.
- Mock the network with MSW 3 (`import { http, HttpResponse } from 'msw/http'`, `import { setupServer } from 'msw/node'`, `server.listen({ onUnhandledFrame: 'error' })`; MSW 2 imports from `msw` and the option is `onUnhandledRequest`), never `fetch` or modules; `vi.mock` only for hard boundaries (time via `vi.useFakeTimers`, randomness, heavy third-party widgets); `vi.when` (Vitest 5+) for argument-specific stubs; Vitest 5 clears mocks between tests by default.
- Render through the real providers (QueryClient with `retry: false`, router memory history, theme) via one `renderWithProviders` helper; `renderHook` for custom hooks; test Server Components at the function level or in a framework test.
- Each test is independent: fresh QueryClient and store per test, no shared mutable module state; `test.each` tables for variants.
- Stories (Storybook 10 + the Vitest addon) double as interaction tests, and as visual tests when a play function asserts a screenshot; axe checks: Accessibility.
- Playwright: `getByRole` locators, web-first assertions (`await expect(locator).toBeVisible()`), no `waitForTimeout`, fixtures for auth and data, trace on failure; cover the critical paths only.
- Name `*.test.tsx` beside the source; describe the behavior (`it('disables submit while pending')`); arrange, act, assert; one behavior per test.

## Tooling & CI (run on every commit)

- Vite 8 (Rolldown) with `@vitejs/plugin-react` v6 (Oxc; the inline `babel` option is gone; `plugin-react-swc` only when SWC plugins are needed), or the framework's bundler (Next.js Turbopack); compiler wiring: Performance.
- ESLint flat config — ESLint 9 while `eslint-plugin-react` and `eslint-plugin-jsx-a11y` are used (their peer ranges stop at 9 and the React plugin crashes on 10), ESLint 10 once every plugin declares support or with `@eslint-react/eslint-plugin` instead: `@eslint/js` recommended, `typescript-eslint` `strictTypeChecked` + `stylisticTypeChecked` with `parserOptions.projectService`, `eslint-plugin-react` `configs.flat.recommended` + `configs.flat['jsx-runtime']`, `eslint-plugin-react-hooks` `configs.flat.recommended` (v7+ carries the compiler rules; `recommended-latest` is the experimental preset, not a default), `eslint-plugin-jsx-a11y` `flatConfigs.recommended`, `eslint-plugin-react-refresh` on Vite. Oxlint or Biome as a fast pre-pass is fine; type-aware rules still come from typescript-eslint. No `eslint-disable` without a reason.
- One formatter (Prettier 3 or Biome 2) enforced in CI; `tsc --noEmit` (or `tsc -b`) as its own step; `knip` for dead exports and dependencies.
- Scripts `lint`, `typecheck`, `test`, `build`, `e2e`; CI runs them plus `audit` on a frozen lockfile (`pnpm install --frozen-lockfile` / `npm ci`); the current Active LTS Node (26 from 2026-10-28; 24 is in maintenance) pinned in `engines` and `.nvmrc`; the package manager pinned in `packageManager`.
- Dev: `<StrictMode>` at the root (double render and double effects surface impure code); React DevTools; Fast Refresh needs component-only module exports (lint `react-refresh/only-export-components`, with the framework's allowlist for route-module exports).

## Project layout & dependencies

- Pick by size: small = flat `src/` (`components/`, `hooks/`, `lib/`); medium/large = feature folders (`features/<name>/{components,hooks,api,types}` with an `index.ts` public surface) plus `components/ui/` (design-system primitives), `lib/<capability>/` (`lib/money`, `lib/http`: framework-agnostic modules named by what they do — no `utils/` or `lib/` dumping ground), and `app/` or `routes/` for the framework's routing.
- Dependencies point inward: routes → features → shared UI and lib; features never import each other's internals (use the feature's `index.ts` or lift to shared); UI primitives know nothing about features or data.
- Tests and stories beside the source; no `index.tsx` components (undiscoverable in editors) — a feature's `index.ts` is the only barrel.
- Framework files (`page.tsx`, route modules) stay thin: load data, compose a feature component; business logic lives in plain TypeScript modules testable without React.
- Approved extras, each with a reason: TanStack Query, Zustand/Jotai, Zod, `react-hook-form`, `clsx`/`tailwind-merge`, a headless UI kit, MSW; check transitive size (`pnpm why`, the bundle analyzer) before adding. Commit the lockfile.
- `package.json`: `"type": "module"`, `engines`, `packageManager`, and `sideEffects` when publishing a library.

## Modern React — prefer over legacy (gate on the installed version)

- **19.0 (Dec 2024):** Actions (`<form action>`, `useActionState`, `useFormStatus`, `useOptimistic`), `use` (promises, context), `ref` as a prop and ref-callback cleanup, `<Ctx>` as provider, document metadata and stylesheet `precedence` hoisting, async `<script>` dedupe, `preload`/`preinit`/`preconnect`/`prefetchDNS` from `react-dom`, `useDeferredValue(value, initialValue)`, hydration-mismatch diffs, root error options, Server Components and Server Functions stable. Removed: `propTypes` and `defaultProps` on functions, legacy context, string refs, `createFactory`, `ReactDOM.render`/`hydrate`/`findDOMNode`/`unmountComponentAtNode`, `react-dom/test-utils` (`act` is in `react`), UMD builds; `react-test-renderer` deprecated → Testing Library; `forwardRef` unnecessary.
- **19.1 (Mar 2025):** `captureOwnerStack` (dev-only debugging), Suspense and hydration fixes.
- **19.2 (Oct 2025):** `<Activity mode>`, `useEffectEvent`, `cacheSignal` (RSC), React Performance Tracks in Chrome DevTools, partial pre-rendering (`prerender` → `resume`/`resumeAndPrerender`), batched Suspense reveals in SSR; `eslint-plugin-react-hooks` v6 flat config (compiler rules opt-in via `recommended-latest`; v7.0.0, Oct 2025, moves them into `recommended`).
- **19.3 (Sep 2026):** `<ViewTransition>` + `addTransitionType` (animates only transition-driven updates — `startTransition`, Suspense reveals, `useDeferredValue`; enter/exit fire only when no DOM node wraps the `<ViewTransition>`, update and share may be nested; shared `name`s unique at any time), Fragment refs (`<Fragment ref>` → `FragmentInstance` with event listeners, focus, `observeUsing`, `scrollIntoView`), `browser()` from `react-dom`, Trusted Types pass-through, Server Components render `<Ctx>` directly, `Error.cause` crosses Flight, `<Activity>` in Flight, StrictMode double-invokes effects on hydration, `onFullscreenChange`.
- **React Compiler 1.0 (Oct 2025):** stable, pin exact; React 17+ via `target`; lint rules in `eslint-plugin-react-hooks` v7 `recommended`.
