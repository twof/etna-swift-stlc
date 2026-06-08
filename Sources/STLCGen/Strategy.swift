import STLC
import PropertyTestingKit
import Foundation
import os

/// Thrown by the fuzz closure when a property is violated; carries the failing
/// term in ETNA wire form so `solve` can report it as the counterexample.
struct PropertyViolation: Error { let wire: String }

/// Outcome of one solve run, shaped for ETNA's (legacy) result JSON.
public struct SolveOutcome: Sendable {
    public let status: String          // "passed" | "failed" | "aborted"
    public let tests: Int
    public let discards: Int
    public let counterexample: String?
    public let error: String?
    public let timeNs: UInt64

    public init(status: String, tests: Int, discards: Int, counterexample: String?, error: String?, timeNs: UInt64) {
        self.status = status
        self.tests = tests
        self.discards = discards
        self.counterexample = counterexample
        self.error = error
        self.timeNs = timeNs
    }
}

private func jsonEscape(_ s: String) -> String {
    var out = ""
    for c in s {
        switch c {
        case "\"": out += "\\\""
        case "\\": out += "\\\\"
        case "\n": out += "\\n"
        case "\t": out += "\\t"
        case "\r": out += "\\r"
        default: out.append(c)
        }
    }
    return out
}

extension SolveOutcome {
    /// ETNA result JSON (matching the shape emitted by the Rust/Python workloads).
    public var json: String {
        let cex = counterexample.map { "\"\(jsonEscape($0))\"" } ?? "null"
        let err = error.map { "\"\(jsonEscape($0))\"" } ?? "null"
        return """
        {"status":"\(status)","tests":\(tests),"discards":\(discards),"counterexample":\(cex),"error":\(err),"time":"\(timeNs)ns","execution_time":null,"generation_time":null,"shrinking_time":null}
        """
    }
}

/// Number of parallel fuzz engines. Defaults to the core count (full parallel):
/// the `stop_at_first_counterexample` plugin halts the finding engine, and PTK's
/// `runEngines` then cancels the siblings (cross-engine early-cancel), so `solve`
/// still returns at the first counterexample with time-to-find. Override with
/// `STLC_PARALLELISM` (e.g. `=1` for a single engine).
let enginesParallelism: Int = {
    if let v = ProcessInfo.processInfo.environment["STLC_PARALLELISM"], let n = Int(v), n > 0 { return n }
    return ProcessInfo.processInfo.processorCount
}()

/// Run the coverage-guided fuzzer over `Expr`, checking `check`. `check` returns
/// the property verdict: `false` is a counterexample, `nil` a discard (ill-typed
/// term), `true` a pass.
private func runFuzz(
    duration: Duration,
    check: @escaping @Sendable (Expr) -> Bool?
) async -> SolveOutcome {
    let discards = OSAllocatedUnfairLock(initialState: 0)
    let start = DispatchTime.now()
    func elapsed() -> UInt64 { DispatchTime.now().uptimeNanoseconds - start.uptimeNanoseconds }

    do {
        let result = try await fuzz(
            duration: duration,
            persistence: .ephemeral,
            parallelism: enginesParallelism,
            plugins: { [.corpusMutation(), .stopOnFirstFailure(reason: .custom("counterexample_found"))] }
        ) { (input: Expr) in
            switch check(input) {
            case .some(false): throw PropertyViolation(wire: input.description)
            case .none: discards.withLock { $0 += 1 }
            case .some(true): break
            }
        }
        return SolveOutcome(status: "passed", tests: result.stats.totalInputs,
                            discards: discards.withLock { $0 }, counterexample: nil, error: nil, timeNs: elapsed())
    } catch let e as FuzzError {
        guard case let .testFailed(_, underlying, _, stats) = e else {
            return SolveOutcome(status: "aborted", tests: 0, discards: discards.withLock { $0 },
                                counterexample: nil, error: "\(e)", timeNs: elapsed())
        }
        return SolveOutcome(status: "failed", tests: stats.totalInputs,
                            discards: discards.withLock { $0 },
                            counterexample: (underlying as? PropertyViolation)?.wire, error: nil, timeNs: elapsed())
    } catch {
        return SolveOutcome(status: "aborted", tests: 0, discards: discards.withLock { $0 },
                            counterexample: nil, error: "\(error)", timeNs: elapsed())
    }
}

/// All property names this workload understands (matches `etna.toml`).
public let stlcProperties = ["SinglePreserve", "MultiPreserve"]

public enum SolveError: Error { case unknownProperty(String) }

/// Coverage-guided solve: fuzz `property` for `duration`. The mutant under test
/// is whichever marauder variant is active in the compiled `STLC` module.
public func solve(property: String, duration: Duration) async throws -> SolveOutcome {
    switch property {
    case "SinglePreserve":
        return await runFuzz(duration: duration, check: { prop_single_preserve($0) })
    case "MultiPreserve":
        return await runFuzz(duration: duration, check: { prop_multi_preserve($0) })
    default:
        throw SolveError.unknownProperty(property)
    }
}

// MARK: - Sampling (cross-language `sample` capability)

/// Generate `count` terms for `property`, each with its generation time (ns) and
/// ETNA wire serialization. Open-loop (no coverage feedback).
public func sample(property: String, count: Int) throws -> [(timeNs: UInt64, wire: String)] {
    guard stlcProperties.contains(property) else { throw SolveError.unknownProperty(property) }
    var rng = FastRNG()
    var out: [(UInt64, String)] = []
    out.reserveCapacity(count)
    for _ in 0..<count {
        let start = DispatchTime.now()
        let value = Expr.defaultMutator.generate(&rng)
        let ns = DispatchTime.now().uptimeNanoseconds - start.uptimeNanoseconds
        out.append((ns, value.description))
    }
    return out
}
