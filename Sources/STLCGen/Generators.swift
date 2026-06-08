import STLC
import PropertyTestingKit

// MARK: - Bespoke well-typed term generator (generation only)
//
// A type-directed generator of CLOSED, WELL-TYPED terms, ported from the ETNA
// bespoke strategy (alpaylan/etna-rust-stlc `src/strategies/bespoke.rs`). It is
// INDEPENDENT of the mutated machinery in `STLC` (`shift`/`subst`/`substTop`):
// it only manipulates the typing context and matches on types, never calling a
// mutatable function. So it keeps producing valid, well-typed inputs regardless
// of which mutant is active — the analog of ETNA's bespoke generators, and the
// reason STLC is tractable at all (a type-based generator of arbitrary `Expr`s
// would be ill-typed ~always and discard everything).
//
// `getTyp` (used by the property to compute the term's type) is itself NOT
// mutated, so the loop is: generate a well-typed term `e : T`; reduce it with
// the mutated `pstep`; check the reduct still has type `T`.

/// Type generator (`gen_typ`): `frequency [(1, TBool), (size, TFun ..)]`.
func genTyp(_ rng: inout FastRNG, _ size: Int) -> Typ {
    if size == 0 { return .TBool }
    // weight TBool=1, TFun=size
    if Int.random(in: 0..<(1 + size), using: &rng) == 0 {
        return .TBool
    }
    return .TFun(genTyp(&rng, size / 2), genTyp(&rng, size / 2))
}

/// Canonical inhabitant of a type (`gen_one`): always succeeds, no application.
func genOne(_ ctx: [Typ], _ t: Typ, _ rng: inout FastRNG) -> Expr {
    switch t {
    case .TBool:
        return .Bool(Bool.random(using: &rng))
    case let .TFun(t1, t2):
        var ctx1 = ctx
        ctx1.insert(t1, at: 0)
        return .Abs(t1, genOne(ctx1, t2, &rng))
    }
}

/// `gen_abs`: a lambda whose body has type `t2` in the extended context.
func genAbs(_ ctx: [Typ], _ t1: Typ, _ t2: Typ, _ rng: inout FastRNG, _ size: Int) -> Expr {
    var ctx1 = ctx
    ctx1.insert(t1, at: 0)
    return .Abs(t1, genExactExpr(ctx1, t2, &rng, size))
}

/// `gen_app`: pick an arbitrary argument type `t'`, build `e1 : t' -> t` and
/// `e2 : t'`. Because `e1` of a function type is often itself an `Abs`, this is
/// the source of the β-redexes that exercise substitution.
func genApp(_ ctx: [Typ], _ t: Typ, _ rng: inout FastRNG, _ size: Int) -> Expr {
    let tPrime = genTyp(&rng, 5)
    let e1 = genExactExpr(ctx, .TFun(tPrime, t), &rng, size / 2)
    let e2 = genExactExpr(ctx, tPrime, &rng, size / 2)
    return .App(e1, e2)
}

/// `gen_exact_expr`: generate a term of EXACTLY type `t` in `ctx`, uniformly
/// over the applicable constructors (`gen_one`, `gen_app`, `gen_abs` when `t` is
/// a function type, and a context variable of type `t` when one exists).
func genExactExpr(_ ctx: [Typ], _ t: Typ, _ rng: inout FastRNG, _ size: Int) -> Expr {
    let varCandidates = ctx.indices.filter { ctx[$0] == t }
    // option tags: 0 = gen_one, 1 = gen_app, 2 = gen_abs, 3 = gen_var
    var options: [Int] = [0]
    if size > 0 {
        options.append(1)
        if case .TFun = t { options.append(2) }
    }
    if !varCandidates.isEmpty { options.append(3) }

    switch options[Int.random(in: 0..<options.count, using: &rng)] {
    case 1:
        return genApp(ctx, t, &rng, size)
    case 2:
        guard case let .TFun(t1, t2) = t else { return genOne(ctx, t, &rng) }
        return genAbs(ctx, t1, t2, &rng, size - 1)
    case 3:
        let idx = varCandidates[Int.random(in: 0..<varCandidates.count, using: &rng)]
        return .Var(idx)
    default:
        return genOne(ctx, t, &rng)
    }
}

/// A closed well-typed term (`ExprOpt::arbitrary`): a random closed type, then a
/// term of that type of bounded size. Size is biased toward non-trivial terms so
/// the generated programs actually contain redexes to reduce.
func genExpr(_ rng: inout FastRNG) -> Expr {
    let t = genTyp(&rng, 4)
    let size = Int.random(in: 2...10, using: &rng)
    return genExactExpr([], t, &rng, size)
}

// MARK: - Mutation (coverage-guided neighbors)
//
// Most neighbors are well-typedness-preserving; some are structural and may be
// ill-typed (the property discards those). The key well-typed move is wrapping
// in an identity redex `(λx:T. x) e`, which manufactures a β-redex so the
// fuzzer can drive coverage into the substitution paths even from a normal form.
func mutateExpr(_ e: Expr) -> [Expr] {
    var out: [Expr] = []
    if let t = mt(e) {
        out.append(.App(.Abs(t, .Var(0)), e))   // identity redex → reduces to e
    }
    switch e {
    case let .App(f, a):
        out.append(f)
        out.append(a)
    case let .Abs(_, body):
        out.append(body)
    case let .Bool(b):
        out.append(.Bool(!b))
    case let .Var(i):
        out.append(.Var(i + 1))
        if i > 0 { out.append(.Var(i - 1)) }
    }
    return out
}

extension Expr: MutatorProviding {
    public static var defaultMutator: Mutator<Expr> {
        Mutator(
            seeds: [
                // Small well-typed redexes spanning the substitution cases.
                .App(.Abs(.TBool, .Var(0)), .Bool(true)),
                .Abs(.TBool, .App(.Abs(.TBool, .Var(1)), .Bool(true))),
                .App(.Abs(.TBool, .Abs(.TBool, .Var(0))), .Bool(false)),
                .Bool(true),
            ],
            mutate: { mutateExpr($0) },
            generate: { genExpr(&$0) }
        )
    }
}
