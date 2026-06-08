@testable import STLC

/// The canonical ETNA STLC witnesses (alpaylan/etna-rust-stlc `etna.toml`): for
/// each of the 10 substitution mutants, a single term that the named property
/// flags as a counterexample on the MUTANT. On the CLEAN implementation, type
/// preservation is a theorem, so every witness must evaluate to `Some true`.
/// Each mutant ships the SAME witness for both `SinglePreserve` and
/// `MultiPreserve` → 20 rows.
struct Witness {
    let mutant: String
    let property: String
    let input: String
    init(_ m: String, _ p: String, _ i: String) {
        mutant = m; property = p; input = i
    }
}

let cleanWitnesses: [Witness] = {
    let pairs: [(String, String)] = [
        ("shift_var_none",          "(Abs TBool (App (Abs TBool (Var 1)) (Bool #t)))"),
        ("shift_var_all",           "(App (Abs TBool (Abs TBool (Var 0))) (Bool #t))"),
        ("shift_var_leq",           "(App (Abs TBool (App (Abs TBool (Abs (TFun TBool TBool) (Var 1))) (Var 0))) (Bool #t))"),
        ("shift_abs_no_incr",       "(App (Abs TBool (Abs TBool (Var 0))) (Bool #t))"),
        ("subst_var_all",           "(Abs (TFun TBool TBool) (App (Abs TBool (Var 1)) (Bool #t)))"),
        ("subst_var_none",          "(App (Abs TBool (Var 0)) (Bool #t))"),
        ("subst_abs_no_shift",      "(App (Abs TBool (App (Abs TBool (Abs (TFun TBool TBool) (Var 1))) (Var 0))) (Bool #t))"),
        ("subst_abs_no_incr",       "(App (Abs TBool (Abs (TFun TBool TBool) (Var 1))) (Bool #t))"),
        ("substTop_no_shift",       "(Abs TBool (App (Abs TBool (Var 1)) (Bool #t)))"),
        ("substTop_no_shift_back",  "(Abs TBool (App (Abs TBool (Var 0)) (Var 0)))"),
    ]
    return pairs.flatMap { (m, i) in
        [Witness(m, "SinglePreserve", i), Witness(m, "MultiPreserve", i)]
    }
}()
