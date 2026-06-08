// STLC type-preservation properties, ported from ETNA's reference workload
// (jwshii/etna `Spec.v`, mirrored by alpaylan/etna-rust-stlc `src/spec.rs`).
//
// Properties return `Bool?` (mirroring the Rust port's `Option<bool>`):
//   - `true`  → property held
//   - `false` → property violated (a real counterexample: a mutated `shift`/
//                `subst` produced an ill-typed term after reduction)
//   - `nil`   → discarded (the input term is ill-typed, so there is no type to
//                preserve — `mt` returned `nil`)
//
// Preservation is a theorem for the clean STLC, so every well-typed input must
// yield `true`; a mutant breaks substitution and reduction escapes the type.

/// Type of a closed term (empty context).
public func mt(_ e: Expr) -> Typ? {
    getTyp([], e)
}

/// Does the closed term `e` have type `t`?
public func mTypeCheck(_ e: Expr, _ t: Typ) -> Bool {
    typeCheck([], e, t)
}

/// Single-step preservation: one `pstep` keeps the type. A term already in
/// normal form (`pstep` → nil) trivially preserves.
public func prop_single_preserve(_ e: Expr) -> Bool? {
    guard let tp = mt(e) else { return nil }
    if let stepped = pstep(e) {
        return mTypeCheck(stepped, tp)
    }
    return true
}

/// Multi-step preservation: up to 40 `pstep`s keep the type.
public func prop_multi_preserve(_ e: Expr) -> Bool? {
    guard let tp = mt(e) else { return nil }
    if let stepped = multistep(40, pstep, e) {
        return mTypeCheck(stepped, tp)
    }
    return true
}
