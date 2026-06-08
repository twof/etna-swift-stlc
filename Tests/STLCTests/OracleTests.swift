import Testing
@testable import STLC

/// Proof that the clean Swift port satisfies STLC type preservation on every
/// canonical ETNA witness: all 20 → `Some true`. Type preservation is a theorem
/// for the correct calculus, so this is the ground-truth oracle (the witnesses
/// only become counterexamples once a `shift`/`subst` mutant is activated).
@Suite("Oracle (STLC type preservation)")
struct OracleTests {

    @Test("Clean implementation preserves types on all canonical witnesses")
    func cleanPreservesTypes() throws {
        for w in cleanWitnesses {
            let result = try evaluate(property: w.property, input: w.input)
            #expect(
                result == true,
                "\(w.mutant)/\(w.property) on \(w.input): expected Some(true) on clean, got \(String(describing: result))"
            )
        }
    }

    @Test("Every witness is well-typed (not discarded)")
    func witnessesWellTyped() throws {
        for w in cleanWitnesses {
            let e = try decodeExpr(parseSExpr(w.input))
            #expect(mt(e) != nil, "\(w.input) should be well-typed")
        }
    }

    @Test("Type wire round-trips, accepting bare and parenthesized TBool")
    func typeDecode() throws {
        #expect(try decodeTyp(parseSExpr("TBool")) == .TBool)
        #expect(try decodeTyp(parseSExpr("(TBool)")) == .TBool)
        let f = try decodeTyp(parseSExpr("(TFun TBool (TFun TBool TBool))"))
        #expect(f == .TFun(.TBool, .TFun(.TBool, .TBool)))
    }

    @Test("Expr wire decodes Var/Bool/Abs/App and round-trips description")
    func exprDecode() throws {
        let s = "(Abs TBool (App (Abs TBool (Var 1)) (Bool #t)))"
        let e = try decodeExpr(parseSExpr(s))
        #expect(e == .Abs(.TBool, .App(.Abs(.TBool, .Var(1)), .Bool(true))))
        // description re-parses to the same term (canonical form uses (TBool)).
        let reparsed = try decodeExpr(parseSExpr(e.description))
        #expect(reparsed == e)
    }

    @Test("getTyp infers basic types")
    func getTypBasics() {
        #expect(getTyp([], .Bool(true)) == .TBool)
        #expect(getTyp([], .Abs(.TBool, .Var(0))) == .TFun(.TBool, .TBool))
        // open term (free var) is ill-typed in the empty context
        #expect(getTyp([], .Var(0)) == nil)
        // type mismatch in application
        #expect(getTyp([], .App(.Bool(true), .Bool(true))) == nil)
    }
}
