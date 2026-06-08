// Simply-typed lambda calculus (De Bruijn), ported from the canonical ETNA STLC
// workload (jwshii/etna, mirrored by alpaylan/etna-rust-stlc `src/implementation.rs`).
//
// The clean (correct) bodies are active; the mutants live inline as marauder
// source-swap variants — commented-out alternative bodies that ETNA activates +
// recompiles per task (see README "Mutants"; marauder.toml registers Swift as a
// custom language). The 10 task mutants all live in `shift` / `subst` /
// `substTop` — the capture-avoiding substitution machinery — so they only
// manifest when a β-redex actually fires under a binder.
//
// Type inference (`getTyp`) and reduction control flow (`pstep`, `multistep`,
// `isNf`) are NOT mutated — only the index-shifting/substitution arithmetic is.

public indirect enum Typ: Equatable, Codable, Sendable {
    case TBool
    case TFun(Typ, Typ)
}

public indirect enum Expr: Equatable, Codable, Sendable {
    case Var(Int)
    case Bool(Bool)
    case Abs(Typ, Expr)
    case App(Expr, Expr)
}

extension Typ: CustomStringConvertible {
    /// Canonical ETNA wire form: `(TBool)`, `(TFun <t1> <t2>)`. The decoder in
    /// `SExpr.swift` also accepts the bare `TBool` spelling the `etna.toml`
    /// witnesses use.
    public var description: String {
        switch self {
        case .TBool: return "(TBool)"
        case let .TFun(p, r): return "(TFun \(p) \(r))"
        }
    }
}

extension Expr: CustomStringConvertible {
    /// Canonical ETNA wire form: `(Var i)`, `(Bool #t|#f)`, `(Abs <typ> <body>)`,
    /// `(App <fun> <arg>)` — matches the `etna.toml` witness format.
    public var description: String {
        switch self {
        case let .Var(i): return "(Var \(i))"
        case let .Bool(b): return "(Bool \(b ? "#t" : "#f"))"
        case let .Abs(t, body): return "(Abs \(t) \(body))"
        case let .App(f, a): return "(App \(f) \(a))"
        }
    }
}

/// Expression size (used by the cross-language `size` metric).
public func exprSize(_ e: Expr) -> Int {
    switch e {
    case .Var, .Bool: return 1
    case let .Abs(_, body): return 1 + exprSize(body)
    case let .App(f, a): return 1 + exprSize(f) + exprSize(a)
    }
}

// MARK: - Typing (De Bruijn; ctx[0] is the innermost binder)

public func getTyp(_ ctx: [Typ], _ expr: Expr) -> Typ? {
    switch expr {
    case let .Var(i):
        if i < 0 || i >= ctx.count { return nil }
        return ctx[i]
    case .Bool:
        return .TBool
    case let .Abs(typ, body):
        var newCtx = ctx
        newCtx.insert(typ, at: 0)
        guard let ret = getTyp(newCtx, body) else { return nil }
        return .TFun(typ, ret)
    case let .App(fun, arg):
        guard let funType = getTyp(ctx, fun) else { return nil }
        guard let argType = getTyp(ctx, arg) else { return nil }
        if case let .TFun(paramType, retType) = funType, paramType == argType {
            return retType
        }
        return nil
    }
}

public func typeCheck(_ ctx: [Typ], _ expr: Expr, _ typ: Typ) -> Bool {
    guard let t = getTyp(ctx, expr) else { return false }
    return t == typ
}

// MARK: - Shifting (de Bruijn index adjustment)

public func shift(_ d: Int, _ expr: Expr) -> Expr {
    func go(_ c: Int, _ e: Expr, _ d: Int) -> Expr {
        switch e {
        case let .Var(i):
            /*| shift_var */
            return i < c ? .Var(i) : .Var(i + d)
            /*|| shift_var_none */
            /*|
            return .Var(i)
            */
            /*|| shift_var_all */
            /*|
            return .Var(i + d)
            */
            /*|| shift_var_leq */
            /*|
            return i <= c ? .Var(i) : .Var(i + d)
            */
            /* |*/
        case let .Bool(b):
            return .Bool(b)
        case let .Abs(typ, body):
            /*| shift_abs */
            return .Abs(typ, go(c + 1, body, d))
            /*|| shift_abs_no_incr */
            /*|
            return .Abs(typ, go(c, body, d))
            */
            /* |*/
        case let .App(fun, arg):
            return .App(go(c, fun, d), go(c, arg, d))
        }
    }
    return go(0, expr, d)
}

// MARK: - Substitution

public func subst(_ n: Int, _ s: Expr, _ e: Expr) -> Expr {
    switch e {
    case let .Var(i):
        /*| subst_var */
        return i == n ? s : .Var(i)
        /*|| subst_var_all */
        /*|
        return s
        */
        /*|| subst_var_none */
        /*|
        return .Var(i)
        */
        /* |*/
    case let .Bool(b):
        return .Bool(b)
    case let .Abs(typ, body):
        /*| subst_abs */
        return .Abs(typ, subst(n + 1, shift(1, s), body))
        /*|| subst_abs_no_shift */
        /*|
        return .Abs(typ, subst(n + 1, s, body))
        */
        /*|| subst_abs_no_incr */
        /*|
        return .Abs(typ, subst(n, shift(1, s), body))
        */
        /* |*/
    case let .App(fun, arg):
        return .App(subst(n, s, fun), subst(n, s, arg))
    }
}

public func substTop(_ s: Expr, _ e: Expr) -> Expr {
    /*| substTop */
    return shift(-1, subst(0, shift(1, s), e))
    /*|| substTop_no_shift */
    /*|
    return subst(0, s, e)
    */
    /*|| substTop_no_shift_back */
    /*|
    return subst(0, shift(1, s), e)
    */
    /* |*/
}

// MARK: - Reduction (parallel small-step) — not mutated

public func pstep(_ expr: Expr) -> Expr? {
    switch expr {
    case let .Abs(t, e):
        guard let ep = pstep(e) else { return nil }
        return .Abs(t, ep)
    case let .App(fun, arg):
        if case let .Abs(_, e1) = fun {
            let e1p = pstep(e1) ?? e1
            let e2p = pstep(arg) ?? arg
            return substTop(e2p, e1p)
        }
        let m1 = pstep(fun)
        let m2 = pstep(arg)
        if m1 == nil && m2 == nil { return nil }
        return .App(m1 ?? fun, m2 ?? arg)
    case .Var, .Bool:
        return nil
    }
}

public func multistep(_ fuel: Int, _ step: (Expr) -> Expr?, _ expr: Expr) -> Expr? {
    var current = expr
    for _ in 0..<fuel {
        if let next = step(current) {
            current = next
        } else {
            return current
        }
    }
    return current
}

public func isNf(_ expr: Expr) -> Bool {
    switch expr {
    case .Var, .Bool:
        return true
    case let .Abs(_, body):
        return isNf(body)
    case let .App(fun, arg):
        if case .Abs = fun { return false }
        return isNf(fun) && isNf(arg)
    }
}
