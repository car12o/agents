---
name: golang
description: Write idiomatic, production-grade Go. Self-contained — all rules inline, no reference files. Use when editing .go files, go.mod, go.sum, or Go tests, or when asked to design, generate, or review Go code. Covers style, errors, concurrency, context, testing, performance, security, modules, JSON, database, production hardening, modern stdlib, tooling, project layout, and anti-patterns.
---

# Skill: golang

Write Go that a senior Go engineer would ship to production. This file is self-contained: every rule is stated inline, with no code snippets — reconstruct each shape with your own knowledge of idiomatic Go, and get the error-prone lines the rules call out right. Gate any version-specific API on the `go` directive in `go.mod`.

> **IMPORTANT: These rules are MANDATORY and MUST be strictly followed without exception.**

## Non-negotiables (every .go file)

- Output passes `gofmt -s` and `goimports`: no unformatted code, no missing or unused imports. Run the formatter before considering work done.
- Match `go.mod`'s `go` directive. Never emit syntax or stdlib APIs newer than declared unless bumping the directive is part of the task.
- Check every error. Discard only with `_ =` and a comment saying why.
- Stdlib first: check whether stdlib covers it before adding a dependency (see the version-gated table below).
- New or changed non-trivial logic ships with a test in the same change.

## Style & naming

- Package names are namespaces; don't stutter (`http.Client`, not `http.HTTPClient`). No `util`/`common`/`helpers` packages — name packages after what they do.
- Group by responsibility/feature, not by noun: a `user` package with `user.go`/`store.go`/`handler.go` beats a `models/` dumping ground. Split a file past ~300 lines.
- Keep `main` thin: load config, wire dependencies, handle signals, call `run(ctx) error`. Business logic lives elsewhere.
- Declare interfaces at the consumer. Accept interfaces, return concrete types. Keep interfaces to 3–4 methods. Don't create an interface for a single implementation with no test seam, and don't return interfaces — let the caller define what it needs.
- Receivers consistent per type: if any method on `T` needs a pointer receiver, all do. Pointer when the method mutates or the struct is large; value for small immutable types.
- Zero values are useful: design so `var x T` is valid (`sync.Mutex`, `bytes.Buffer`, `strings.Builder` all zero-work). No constructor whose only job is zeroing fields; no required `Init()` call.
- Embedding is composition, not inheritance. Use explicit fields when you don't want method promotion.
- `iota` enums: use a sentinel zero value (`StatusUnknown`) when an uninitialized field must be invalid; generate `String()` with `//go:generate stringer`.
- `init()` is for driver registration only — no network, no file I/O, no side effects that complicate testing.
- Constructor injection for DI; wire dependencies in `main`/`run` (the composition root). No DI frameworks.
- Functional options for constructors with >2 optional params; a plain config struct is simpler for internal code with few options.
- Domain types over primitives: `time.Duration` not int ms, `netip.Addr` not string IP, `url.URL` not string URL.
- `net/http` 1.22+ routing (`mux.HandleFunc("GET /users/{id}", h)` + `r.PathValue("id")`; `GET /{$}` matches the root exactly, `GET /files/{path...}` is a catch-all) covers most REST APIs; reach for chi/echo only for middleware groups, regex constraints, or complex routing.
- HTTP middleware: `type Middleware func(http.Handler) http.Handler`; a `Chain(h, mw...)` helper applies them in reverse (`for i := len(mw)-1; i >= 0; i--`) so the first-listed middleware is the outermost wrapper.
- Load config once at startup and pass it as a value; don't read env vars deep inside the app. Validate at load — required vars present, numeric ranges sane — and fail fast with a clear error.

## Documentation (godoc)

- Doc comment on every exported identifier; start with the declared name, complete sentence, present tense ("Client manages…"). Separate paragraphs with blank lines; don't hand-wrap aggressively — leave reflow to the renderer.
- No comment that only restates the name — omit it, or rename the identifier to be self-describing. `//nolint` is a last resort.
- One package comment per package (above any one `package` clause; long ones go in `doc.go`).
- `Deprecated:` marker must be its own paragraph (blank line before) for tools to detect it.
- `Example*` functions in `_test.go` are runnable, verified docs — prefer over prose. Naming: `ExampleFoo`, `ExampleClient_Publish`, `ExampleClient_Publish_withRetry`.
- 1.19+ doc markup: `# Heading`, `[Identifier]` links, and `-`/`1.` lists with a preceding blank line.

## Project layout & dependencies

- Pick structure by size: small project = flat files in one package; medium/large = `cmd/app/main.go` plus flat domain packages (`user/`, `order/`), each holding its types, service, and store interface.
- Don't add `pkg/` unless publishing a library; don't add `internal/` for a single-domain app.
- Dependencies point inward: adapters (HTTP/gRPC) import domain packages; domain never imports adapters or sibling domains. Shared infra goes in `platform/`/`infra/`.
- Cross-domain calls go through a consumer-owned interface (`order` accepts a `UserGetter`, not `user.Service`); wire the concrete impl in `main`.
- Convert transport types → domain types at the boundary; internal code never touches JSON tags, protobuf messages, or `sql.Row`, and never returns implementation types (`*sql.Row`, `*http.Response`) — return your own. Adapters are thin: parse input, call a service, format output — no business logic.
- Generics for type-independent logic (collections, algorithms); concrete types or interfaces when behavior varies. Constraints: `any`, `comparable`, `cmp.Ordered`.

## Errors

- Wrap with `fmt.Errorf("op: %w", err)` when crossing a package boundary or adding context the caller lacks; bare `return err` when the function name already conveys it — don't over-wrap.
- `%v` instead of `%w` to deliberately break the chain (hide the underlying error from `errors.Is`/`As`).
- Handle once: log+handle at the boundary that handles, return everywhere else — never both (duplicate noise).
- Sentinel errors (`var ErrNotFound = errors.New(...)`) for conditions callers check; custom types when callers need structured data. Match with `errors.Is`/`errors.As`, never `==` on a wrapped error.
- Check what an error *can do*, not its concrete type, via a small interface (`interface{ Timeout() bool }`). `Temporary()` is deprecated (1.18) — use `Timeout()` or specific conditions.
- `errors.Join` (1.20+) to aggregate: batch operations, and deferred close — `defer func(){ err = errors.Join(err, f.Close()) }()`.
- Map storage/transport errors to domain errors at layer boundaries (`sql.ErrNoRows` → `ErrNotFound`); an HTTP handler then switches on `errors.Is` to status codes.
- Distinguish transient (5xx, network) from permanent (4xx) failures for retry decisions.
- `panic` only for unrecoverable programmer errors (impossible state, broken invariants) — never control flow or expected failures. Recover at deliberate isolation boundaries (HTTP middleware) and convert to a 500 + logged `debug.Stack()`.

## Context

- First parameter, named `ctx`, on every function that does I/O, blocks, or calls out of process. Never store it in a struct.
- `context.Background()` in main/setup/tests; `context.TODO()` as a placeholder when the source isn't wired yet.
- `WithValue` only for request-scoped metadata (trace IDs, auth claims) with an unexported key type — never for dependency injection.
- Check `ctx.Err()` before expensive work in long-running loops.
- Background work outliving a request: `bgCtx, cancel := context.WithTimeout(context.WithoutCancel(r.Context()), d)` (1.21+) — detach from the request, then bound with a deadline. Always `defer cancel()` (in the spawned goroutine if the work is async) — a `WithTimeout` cancel must be called or the context leaks until the deadline fires.
- `context.WithCancelCause(ctx)` (1.20+) returns a `cancel(err)` that records *why*: `context.Cause(ctx)` returns that error, while `ctx.Err()` still reports the generic `context.Canceled` — use it to propagate an abort reason to downstream callers.
- `context.AfterFunc(ctx, cleanup)` (1.21+) for a done-callback — cheaper than a goroutine waiting on `<-ctx.Done()`; it returns a `stop`, `defer stop()` if no longer needed.

## Concurrency

- Every goroutine needs a shutdown path (context, done channel, or errgroup) — otherwise it leaks → eventual OOM.
- Start goroutines in the caller; the caller owns lifecycle and concurrency strategy.
- `errgroup` over bare `WaitGroup` when goroutines can fail; `g.SetLimit(n)` for bounded fan-out. `errgroup.Go` converts panics into returned errors.
- A bare `go func()` at a deliberate isolation boundary (middleware, supervisor) must `recover` and report; goroutines elsewhere still need a shutdown path but should let panics surface (`errgroup` converts them to returned errors).
- Mutexes for shared state, channels for signaling/orchestration. Don't reach for channels where a mutex is simpler.
- Maps are not goroutine-safe (concurrent read+write panics) — `sync.Mutex`+map, or `sync.Map` for read-heavy disjoint keys. A nil map panics on write; always `make()`.
- Channel pipeline/fan-in: every producer closes its channel and respects `ctx`; consumers `select` on `<-ctx.Done()` so a send never blocks forever after the reader stops.
- Worker pool over a shared `jobs` channel: `n` workers each `range` the channel and `select` their result-send against `<-ctx.Done()`; close `jobs` to signal completion, then `wg.Wait()` before `close(results)`. Reach for this over `errgroup` when work arrives continuously rather than from a fixed slice.
- Rate limiting: `golang.org/x/time/rate` (`limiter.Wait(ctx)`), not a ticker plus a goroutine per request.
- `sync.Once` / `sync.OnceValue`/`OnceValues` (1.21+) for lazy singletons; `OnceValues` returns value+error.
- `singleflight` (`golang.org/x/sync`) to dedupe concurrent calls for one key (cache stampede); run the shared call under a context not tied to any single caller, so a canceller can't poison the flight. `Do` returns a `shared bool` (and `DoChan`'s `Result.Shared`) reporting whether the value went to more than one caller.
- Go 1.22+ (per `go.mod`) gives each loop iteration its own variable — the `v := v` re-bind before `go`/`g.Go` is no longer needed; pre-1.22 code still must re-bind.

## Boundaries, validation & security

- Validate at the boundary: size-limit bodies (`http.MaxBytesReader`), `io.LimitReader` for decompression output, parse into typed values, reject invalid input early.
- Parameterized SQL only — never interpolate user input. Same principle for any interpreter (shell, HTML templates, LDAP).
- Subprocess: `exec.CommandContext` with explicit args, never `sh -c` strings. Separate flags from positional args with `--`, allowlist subcommands, validate input lexically (defeats flag smuggling like `--upload-pack=`).
- Path traversal: `os.Root`/`os.OpenRoot` (1.24+) confines ops to a subtree (OS-enforced); pre-1.24 use `filepath.Clean` + verify prefix.
- `crypto/rand` for security-sensitive randomness (tokens, keys); `math/rand/v2` (1.22+) for non-security use (shuffle, sample) — avoid legacy `math/rand`.
- No hardcoded secrets — env vars, file mounts, secret stores. Never log secrets, raw tokens, full headers, or full request bodies; log method/path/status only.
- Run `govulncheck ./...` when adding or upgrading dependencies.
- Shed excess load early: a bounded semaphore (`chan struct{}`) returns 429 when full rather than queueing unboundedly.

## Database (`database/sql`)

- `sql.Open` doesn't connect — always `PingContext` at startup and fail fast.
- Pool: `SetMaxOpenConns` (~expected concurrency), `SetMaxIdleConns`, `SetConnMaxLifetime` (recycle to pick up DNS changes), `SetConnMaxIdleTime`.
- Always the `...Context` variants and parameterized placeholders.
- Transactions: `BeginTx` → `defer tx.Rollback()` (no-op after Commit) → operate on `tx` (not `db`) → `tx.Commit()`.
- Multi-row: `defer rows.Close()`, loop `rows.Next()`/`rows.Scan`, then check `rows.Err()` after the loop — it catches errors that ended iteration (network, cancelled ctx).
- Single row: `QueryRowContext(...).Scan(...)`; map `sql.ErrNoRows` → domain `ErrNotFound` at the store layer.
- Nullable columns: `sql.Null[T]` (1.22+) or pointer fields (`*string`, nil = NULL; pairs well with JSON `omitempty`). Use `sql.Null*` when you need the Valid/zero distinction or want to avoid pointer indirection in hot paths.
- Use a migration tool (goose, golang-migrate, atlas) — don't hand-roll. Keep `migrations/` versioned; apply at startup (simple service) or as a separate CI step (shared DB).

## JSON & encoding

- Struct tags: `json:"name"`; `,omitempty` skips zero `""`/0/nil/false; `,omitzero` (1.24+) calls `IsZero()` — correct for `time.Time` and custom types where `omitempty` misbehaves; `json:"-"` is never marshalled.
- Streaming: `json.NewDecoder(r)` / `json.NewEncoder(w)` over buffering the whole body; `dec.DisallowUnknownFields()` for strict parsing; `dec.UseNumber()` to preserve large/precise integers.
- Custom `MarshalJSON`/`UnmarshalJSON` for wire-format control and enum validation on unmarshal.
- `json.RawMessage` for envelope-then-dispatch partial parsing.
- Write responses through a helper that encodes to a buffer *first*, then sets `Content-Type` and status — so an encode error becomes a clean 500, not a half-written body. Log (don't silently drop) the final `w.Write` error.

## Testing

- Table-driven by default; name cases; `t.Run`.
- Test behavior, not implementation — tests that break on refactor are a liability.
- `t.Helper()` in every helper; `t.Cleanup()` over `defer` in helpers (fires at test end, after the caller has used the resource).
- `package foo_test` for black-box public-API tests; `package foo` only when you need unexported access.
- Prefer fakes (real in-memory behavior) over mocks; stub for canned inputs; mock only to verify interactions (it couples tests to implementation). `cmp.Diff` (with `cmpopts.IgnoreUnexported`/`EquateApprox`/`SortSlices`) for readable assertions.
- HTTP handlers: drive them with `httptest.NewRequest` + `httptest.NewRecorder`, then assert on `rec.Result()` status/headers/body — no real socket or port.
- `t.Context()` (1.24+): context cancelled at test end — use over hand-rolled background+cancel; in a subtest it's cancelled when *that* subtest ends.
- `b.Loop()` (1.24+) in benchmarks instead of `for range b.N` (prevents dead-code elimination); run `go test -bench=. -benchmem`.
- `testing/synctest`: deterministic concurrency tests — enter with `synctest.Test(t, func(t *testing.T){...})`; inside the bubble, fake time advances only when all goroutines block (so `time.Sleep` is instant), and bubble goroutines can't race with code outside it.
- Golden files: compare against `testdata/*.golden`, regenerate behind an `-update` flag.
- Fuzz: `f.Add` seeds + `f.Fuzz(func(t, input){...})`; return early on expected-invalid input.
- Integration tests behind `//go:build integration` + a `testing.Short()` skip; run with `-tags=integration`.
- `t.Parallel()` on the test and each subtest to parallelize.
- Race detector unconditionally in CI: `go test -race ./...` (~2–10× overhead — tests only, never production binaries).

## Testify (only if the project already uses it; otherwise stdlib + `cmp.Diff`)

- `require` for preconditions (the next line dereferences the result), `assert` for value checks. `assert.New(t)`/`require.New(t)` return an object bound to `t` so you stop passing `t` on every call.
- Match errors by behavior: `ErrorIs`/`ErrorAs`/`ErrorContains` survive wrapping; `assert.Equal` only for sentinels you own and know are unwrapped.
- Assertion families (all in both `assert` and `require`): equality `Equal`/`NotEqual`/`EqualValues`; errors `NoError`/`Error`/`ErrorIs`/`ErrorAs`/`ErrorContains`; collections `Contains`/`Len`/`Empty`/`NotEmpty`/`ElementsMatch` (order-independent)/`Subset`; numeric `Greater`/`Less`/`InDelta` (absolute)/`InEpsilon` (relative); structural `JSONEq`/`YAMLEq` (semantic, ignore key order); async `Eventually`/`EventuallyWithT`/`Never` (poll a condition — use these for async paths, never `time.Sleep`).
- Prefer fakes; reach for `testify/mock` only to verify interactions. Always `mock.AssertExpectations(t)` (or in `TearDownTest`) — unmet expectations silently pass otherwise.
- Exact arg values by default; `mock.MatchedBy(fn)` only when a value isn't knowable upfront (generated IDs/timestamps).
- Mock call config: `.Once()`/`.Twice()`/`.Times(n)` bound the call count, `.Return(...)` sets results, `.Run(func(mock.Arguments))` runs a side effect, `mock.InOrder(...)` enforces call sequence.
- Suites only for shared expensive setup; needs the `TestXxxSuite` entry point (`suite.Run`) or it's silently skipped. Hooks: `SetupSuite`/`TearDownSuite` (once), `SetupTest` (per test), `s.Run(name, fn)` for subtests with `SetupSubTest`/`TearDownSubTest`. When the suite owns mocks, call `AssertExpectations` in `TearDownTest` or expectations pass silently.

## Performance (benchmark before optimizing — intuition is wrong)

- Preallocate when size is known: `make([]T, 0, n)`.
- `strings.Builder` (with `Grow`) for loop concatenation, not `+=`.
- `range` copies each element — for large structs iterate by index (`&items[i]`) or use a slice of pointers.
- `sync.Pool` for hot-path allocations: always `Reset` before `Put`, always copy data out before returning to the pool (it may be reused immediately). Benchmark first.
- Value receivers can avoid heap allocation for small types; escape analysis decides — `go build -gcflags='-m=2'` shows escapes. Common escapes: returning or storing a pointer to a local, putting a value in an interface, a closure capturing a variable that outlives the call. Reducing allocations is the highest-leverage win.
- `go test -bench` + `pprof` (`-cpuprofile`, `go tool pprof`) to find hotspots — not guesswork.

## Building a long-running service

- HTTP clients: create once, reuse, set explicit `Timeout`; configure the `Transport` pool (`MaxIdleConns`, `MaxIdleConnsPerHost`, `IdleConnTimeout`, `TLSHandshakeTimeout`). Use `http.NewRequestWithContext`; size-limit response bodies with `io.LimitReader`.
- HTTP servers: set `ReadHeaderTimeout` (defeats Slowloris), `ReadTimeout`, `WriteTimeout` (omit or override per-handler for streaming), `IdleTimeout`.
- Health: split `/healthz` (process liveness, no external deps — or k8s restarts you for nothing) from `/readyz` (dependency readiness, e.g. `db.PingContext`).
- Retries: idempotent only, bounded attempts, exponential backoff capped then *fully* jittered (`rand` across the whole interval, not added to it); wait on a timer inside a `select` against `<-ctx.Done()` (stop the timer and return `ctx.Err()` on cancel). Skip permanent (4xx) failures via an `isRetryable` check.
- Graceful shutdown: `signal.NotifyContext` for SIGINT/SIGTERM; run `ListenAndServe` in a goroutine that normalizes `http.ErrServerClosed` to nil and reports on a buffered error channel; `select` on the signal *and* that channel (the server can die on its own — bind failure). On signal, `srv.Shutdown` under a bounded `context.WithTimeout` to drain, then close dependencies in reverse startup order, aggregating with `errors.Join`.
- Streaming (SSE/long-poll/chunked): `http.NewResponseController(w)` (1.20+) for flush, per-response deadlines (`SetReadDeadline`/`SetWriteDeadline`), and `Hijack` — it walks middleware writer chains, unlike `w.(http.Flusher)` assertions. These return `errors.ErrUnsupported` when the underlying writer can't honor them — check and fall back gracefully.
- Observability: `log/slog` (JSON handler, `slog.With` for scoped fields, `LogAttrs` in hot paths to avoid variadic allocation); OpenTelemetry + `otelhttp` for traces/metrics; `net/http/pprof` in dev/staging only (never a public port).

## Modules

- One module per deployable; multi-module only for independently released libraries (each its own `go.mod`/tags; `go.work` for local dev, don't commit it for deployables).
- Honest `go` directive — don't claim a version whose features you don't use, or use features newer than you claim. The `toolchain` directive (1.21+, e.g. `toolchain go1.24.2`) pins the exact build toolchain independent of the `go` language-version minimum; let `go get go@1.24` manage it rather than hand-editing.
- Prefer stdlib; fewer deps = fewer problems. Run `go mod tidy` regularly.
- `go get pkg@version` to pin, `go get -u ./...` for a patch sweep. `replace`/`exclude` sparingly (main-module only; friction for downstream consumers).
- Vendoring is optional (reproducible builds without proxy access): `go mod vendor` populates `vendor/`, `go build -mod=vendor` builds from it. Most teams skip it and rely on `GOPROXY` + `go.sum` integrity instead.

## Modern stdlib — prefer over third-party / hand-rolled (gate on `go.mod` version)

- **1.21+:** `slices`/`maps` (`Sort`, `Contains`, `SortFunc`, `BinarySearch`, `Clone`, `Copy`, `Keys`, `Values`, `DeleteFunc`) replace `samber/lo`; `min`/`max`/`clear` builtins; `cmp.Compare` replaces hand-rolled comparators; `log/slog` replaces logrus/zap; `context.WithoutCancel`/`AfterFunc`; `sync.OnceValue`/`OnceValues`.
- **1.22+:** per-iteration loop variables; `range` over ints (`for i := range 10`); `net/http` method+wildcard routing replaces gorilla/mux; `math/rand/v2`; `sql.Null[T]`.
- **1.23+:** `slices.Collect`/`Values`/`All` + `maps.Collect` bridge iterators (`iter.Seq`/`Seq2`, range-over-func; write one as `func All() iter.Seq2[K,V] { return func(yield func(K,V) bool) { ... } }`); unreferenced timers are GC-collectible (`time.After` in loops no longer leaks — still `Stop()`, and drain the channel where an already-fired timer would deliver a stale tick, in select loops); `unique` package (`unique.Make` returns a comparable `Handle[T]` for interned values — pointer-equality comparison, lower memory for high-cardinality keys).
- **1.24+:** tool directives in `go.mod` (a `tool (...)` block) replace `tools.go`, run via `go tool <name>` (e.g. `go tool stringer`); `omitzero` tag; `os.Root`; `t.Context()`; `b.Loop()`; `weak` package (`weak.Pointer[T]` for canonicalization caches that must not prevent GC).
- `fmt.Errorf("...%w", err)` + `errors.Is`/`As` replaces `pkg/errors`. `//go:embed` (`embed.FS`, which implements `io/fs.FS` — pass it to anything taking an `fs.FS`) for static assets, migrations, templates.

## Tooling & CI (run on every commit)

- `go vet ./...`, `go test -race -cover ./...`, `staticcheck ./...`, `golangci-lint run`, `govulncheck ./...`.
- Pin `setup-go` to `go-version-file: go.mod` so CI matches the module's Go version — no drift.
- `.golangci.yml`: start with errcheck/govet/ineffassign/staticcheck/unused/gosec/revive/gocritic/misspell; don't enable everything (false positives drown real issues). Exclude `vendor`/`testdata`.
- Pre-commit/Makefile: `gofmt -s -w .`, `goimports -w .`, `go vet`.

## Anti-patterns (avoid)

- Getter/setter with no invariant — export the field.
- `nil` meaning "use the default" — use functional options or zero-value-ready types.
- Reaching for `any`, `map[string]any` as a struct, or naked `interface{}` in storage — defers type errors to runtime; use generics, specific interfaces, or concrete types.
- Giant interfaces — split into focused 3–4 method ones.
- Bare goroutine without a shutdown path; `go func()` without recover at an isolation boundary.
- `context.WithValue` as DI; storing context in a struct field.
- Returning interfaces instead of concrete types.
- Ignoring `ctx.Err()` in long loops — shutdown stalls.
- `time.After` in pre-1.23 loops (timer leak); `defer` in a hot loop (defers stack until return — extract the body to a function so each defer fires per iteration).
- `init()` doing real work (connections, I/O).
- Logging *and* returning the same error.
