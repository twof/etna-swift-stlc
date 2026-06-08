# etna-swift-stlc

A **simply-typed lambda calculus (STLC) workload for
[ETNA](https://github.com/alpaylan/etna-cli)**, implemented in **Swift** with
**[PropertyTestingKit](https://github.com/doordash-oss/PropertyTestingKit)**
(PTK) as a **coverage-guided** testing strategy.

It is a faithful port of ETNA's reference STLC workload (the hand-written Coq in
[`jwshii/etna`](https://github.com/jwshii/etna), mirrored by
[etna-rust-stlc](https://github.com/alpaylan/etna-rust-stlc)): the same De Bruijn
`Expr`/`Typ`, the same `shift`/`subst`/`pstep` reduction machinery, the same 2
preservation properties, and the same 10 mutants with the same ground-truth
witnesses. The novelty is the **strategy**: PTK drives the search with
**edge-coverage feedback** over a **bespoke well-typed term generator** — the
coverage-guided analog of QuickChick's `FuzzChick`.

This is the third Swift/PTK ETNA workload, after
[etna-swift-bst](https://github.com/twof/etna-swift-bst) and
[etna-swift-rbt](https://github.com/twof/etna-swift-rbt). STLC is the
type-theory workload: the bugs live in capture-avoiding substitution, and the
property is **type preservation** — a well-typed term stays well-typed under
reduction.

## The workload

- **Terms** `Expr = Var Int | Bool Bool | Abs Typ Expr | App Expr Expr` over
  **types** `Typ = TBool | TFun Typ Typ`, De Bruijn-indexed.
- **Machinery**: `getTyp` (type inference), `shift`, `subst`, `substTop`, `pstep`
  (parallel one-step reduction), `multistep`.
- **Properties** (`Bool?` — `nil` discards an ill-typed input):
  - `SinglePreserve` — `pstep` preserves the type.
  - `MultiPreserve` — up to 40 `pstep`s preserve the type.
- **10 mutants**, all in the substitution machinery: `shift_var_none`,
  `shift_var_all`, `shift_var_leq`, `shift_abs_no_incr`, `subst_var_all`,
  `subst_var_none`, `subst_abs_no_shift`, `subst_abs_no_incr`,
  `substTop_no_shift`, `substTop_no_shift_back`.

Type preservation is a *theorem* for the clean calculus, so every canonical
witness evaluates to `Some true` on the clean implementation
(`Tests/STLCTests/OracleTests`) and becomes a counterexample only once its
mutant is active.

### The generator is the crux

A *type-based* generator of arbitrary `Expr`s is ill-typed almost always, so the
property would discard ~everything and catch nothing. `Sources/STLCGen/` instead
ports ETNA's **bespoke** type-directed generator (`gen_exact_expr`): given a
target type and a context, it builds a term of *exactly* that type. It is kept
**independent of the mutated `shift`/`subst`** (it only manipulates the typing
context), so it keeps producing valid, well-typed inputs regardless of which
mutant is active — the STLC analog of the valid-by-construction generators in
`etna-swift-rbt`. PTK then layers edge-coverage feedback on top.

## Layout

| Path | Role |
|---|---|
| `Sources/STLC/` | System under test (`Expr`/`Typ`, `getTyp`, `shift`, `subst`, `substTop`, `pstep`), spec (2 properties), S-expr decoder, and the mutants. No PTK dependency; `-sanitize-coverage` instrumented. |
| `Sources/STLCGen/` | PTK-backed bespoke well-typed term generator + the coverage-guided `solve(...)` and `sample(...)` strategy. |
| `Sources/Solve/` | The `stlc` executable (ETNA `solve`). Target dir is `Solve`, not `stlc`, to avoid a case-insensitive-filesystem clash with `STLC`. |
| `Sources/stlc-sampler/` | The `stlc-sampler` executable (ETNA `sample`). |
| `Tests/STLCTests/` | Oracle (all canonical witnesses preserve types on clean) + generator well-typedness invariant. |
| `etna.toml`, `steps.json` | ETNA workload manifest + capability protocol. |
| `marauder.toml` | Registers Swift as a marauder custom language. |
| `scripts/` | Toolchain build wrapper + run wrappers + `detect.sh` repro. |

## Building & running

PTK requires the **patched Swift toolchain** (parameter packs) and **macOS 26**,
so build via the wrapper rather than system `swift`:

```bash
# Point at your local toolchain build (default shown); Xcode-beta SDK is used.
export BUILD_ROOT=/path/to/OpenSourceDev/build/Ninja-RelWithDebInfoAssert
./scripts/swift-toolchain.sh build      # builds stlc + stlc-sampler
./scripts/swift-toolchain.sh test       # runs the oracle + generator tests
```

`Package.swift` depends on PropertyTestingKit via the **relative path
`../PropertyTestingKit`** (PTK is unreleased and built from a local checkout), so
the PTK checkout must sit beside this workload. Under ETNA the workload is cloned
to `<experiment>/workloads/stlc-swift/`, so symlink PTK next to it:

```bash
ln -s /path/to/PropertyTestingKit <experiment>/workloads/PropertyTestingKit
```

Run the solver (the run wrappers put the toolchain runtime on the dylib path):

```bash
# stlc <strategy> <property> [duration_seconds]   (strategy: "ptk")
./scripts/run-stlc.sh ptk SinglePreserve 10
```

## Mutants

Mutants are applied with ETNA's **marauder source-swap**: the active variant
lives inline in `Sources/STLC/Lang.swift` as commented-out alternative bodies
(`/*| label */ … /*|| variant */ /*| … */ /* |*/`), and ETNA activates one +
recompiles per task. `marauder.toml` registers Swift as a custom language.

Reproduce detection (activate each mutant, rebuild, solve):

```bash
export MARAUDER_CONFIG="$PWD/marauder.toml"
./scripts/detect.sh 5     # all 10 mutants caught by SinglePreserve
```
