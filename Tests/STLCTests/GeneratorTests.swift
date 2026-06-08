import Testing
@testable import STLC
@testable import STLCGen
import PropertyTestingKit

/// The bespoke generator's defining invariant: it must emit ONLY well-typed
/// closed terms, regardless of which mutant is active (it never touches the
/// mutated `shift`/`subst`). If it ever produced an ill-typed term the property
/// would discard it, starving the search — the STLC analog of the RBT
/// "valid-by-construction" requirement.
@Suite("Bespoke generator")
struct GeneratorTests {

    @Test("Every generated term is well-typed (closed)")
    func generatesWellTyped() {
        var rng = FastRNG()
        for _ in 0..<5_000 {
            let e = genExpr(&rng)
            #expect(mt(e) != nil, "generated ill-typed term: \(e)")
        }
    }

    @Test("Generator produces redexes (reducible terms), not just normal forms")
    func generatesRedexes() {
        var rng = FastRNG()
        var reducible = 0
        for _ in 0..<2_000 where pstep(genExpr(&rng)) != nil {
            reducible += 1
        }
        // A workload that never generates a redex can't exercise substitution.
        #expect(reducible > 0, "generator never produced a reducible term")
    }
}
