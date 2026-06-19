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

// MARK: - Pool dynamics probe (temporary diagnostics, PTK_POOL_PROBE=1)

/// Per-engine pool-event counter for diagnosing flood control: pool size,
/// admission rate, and burst run lengths (consecutive same-parent mutants —
/// a run shorter than the burst length means the burst was abandoned).
/// Confined to its engine's task; no synchronization needed internally.
final class PoolProbe: PoolPlugin {
    var iterations = 0
    var poolIterations = 0
    var generatedIterations = 0
    var accepts = 0
    var inserts = 0
    var removes = 0
    var insertSizes: [Int] = []
    /// Real expression size (wire `description.count`) of every admitted entry.
    var insertExprSizes: [Int] = []
    /// Live entries' real expression size, keyed by pool id; an entry drops out
    /// on `.removed`, so at report time this is the size distribution of the
    /// pool that actually survived (post-REDUCE).
    var liveExprSize: [Int: Int] = [:]
    var runLengths: [Int] = []
    /// The most recent accepted iteration's real input size, stashed so the
    /// `.inserted` that immediately follows it (same task, same `observe` call)
    /// can attribute the entry's true expression size — `.inserted` itself
    /// carries only the coverage, not the input size.
    private var lastInputSize: Int?
    private var currentParent: Int?
    private var currentRun = 0

    func handle(event: PoolEvent) -> [PoolAction] {
        switch event {
        case let .iteration(outcome):
            iterations += 1
            if outcome.newCoverage != nil {
                accepts += 1
                lastInputSize = outcome.inputSize
            }
            switch outcome.source {
            case let .pool(parent):
                poolIterations += 1
                if parent == currentParent {
                    currentRun += 1
                } else {
                    flushRun()
                    currentParent = parent
                    currentRun = 1
                }
            case .generated:
                generatedIterations += 1
                flushRun()
            case .queue:
                flushRun()
            }
        case let .inserted(id, coverage, _, _, _):
            inserts += 1
            insertSizes.append(coverage.count)
            let exprSize = lastInputSize ?? coverage.count
            insertExprSizes.append(exprSize)
            liveExprSize[id] = exprSize
        case let .removed(id):
            removes += 1
            liveExprSize[id] = nil
        case .willDraw: break
        }
        return []
    }

    private func flushRun() {
        if currentRun > 0 { runLengths.append(currentRun) }
        currentParent = nil
        currentRun = 0
    }

    func finish() { flushRun() }
}

/// Gathers every engine's probe; the workload prints the aggregate to stderr
/// after the run (stdout is reserved for the ETNA result JSON).
final class ProbeCollector: @unchecked Sendable {
    static let shared = ProbeCollector()
    private let lock = NSLock()
    private var probes: [PoolProbe] = []

    func register(_ probe: PoolProbe) {
        lock.lock()
        probes.append(probe)
        lock.unlock()
    }

    func report(burstLength: Int) -> String {
        lock.lock()
        defer { lock.unlock() }
        for p in probes { p.finish() }
        let iters = probes.map(\.iterations).reduce(0, +)
        let pool = probes.map(\.poolIterations).reduce(0, +)
        let gen = probes.map(\.generatedIterations).reduce(0, +)
        let accepts = probes.map(\.accepts).reduce(0, +)
        let inserts = probes.map(\.inserts).reduce(0, +)
        let removes = probes.map(\.removes).reduce(0, +)
        let sizes = probes.map { $0.inserts - $0.removes }
        let runs = probes.flatMap(\.runLengths)
        let sizes2 = probes.flatMap(\.insertSizes).sorted()
        let medSize = sizes2.isEmpty ? 0 : sizes2[sizes2.count / 2]
        let p90Size = sizes2.isEmpty ? 0 : sizes2[min(sizes2.count - 1, sizes2.count * 9 / 10)]
        let complete = runs.filter { $0 >= burstLength }.count
        let meanRun = runs.isEmpty ? 0 : Double(runs.reduce(0, +)) / Double(runs.count)
        func pct(_ a: Int, _ b: Int) -> String { b == 0 ? "n/a" : String(format: "%.1f%%", 100.0 * Double(a) / Double(b)) }
        func stats(_ xs: [Int]) -> String {
            guard !xs.isEmpty else { return "n=0" }
            let s = xs.sorted()
            let mean = Double(s.reduce(0, +)) / Double(s.count)
            let med = s[s.count / 2]
            let p90 = s[min(s.count - 1, s.count * 9 / 10)]
            return "n=\(s.count) mean=\(String(format: "%.1f", mean)) med=\(med) p90=\(p90) max=\(s[s.count - 1])"
        }
        // Real expression size (wire length): of every admitted entry, and of
        // the entries STILL LIVE at the end (post-REDUCE survivors).
        let admittedExpr = probes.flatMap(\.insertExprSizes)
        let liveExpr = probes.flatMap { Array($0.liveExprSize.values) }
        return """
        POOL_PROBE engines=\(probes.count) iters=\(iters) accepts=\(accepts) (\(pct(accepts, iters)) of iters) \
        inserts=\(inserts) (\(pct(inserts, accepts)) of accepts) removes=\(removes) \
        poolSize mean=\(sizes.isEmpty ? 0 : sizes.reduce(0, +) / sizes.count) max=\(sizes.max() ?? 0) \
        iterMix pool=\(pct(pool, iters)) generated=\(pct(gen, iters)) \
        bursts=\(runs.count) complete=\(pct(complete, runs.count)) meanRun=\(String(format: "%.1f", meanRun)) \
        insertSize med=\(medSize) p90=\(p90Size)
        POOL_PROBE exprSize admitted[\(stats(admittedExpr))] live[\(stats(liveExpr))]
        """
    }
}

/// Run the coverage-guided fuzzer over `Expr`, checking `check`. `check` returns
/// the property verdict: `false` is a counterexample, `nil` a discard (ill-typed
/// term), `true` a pass.
private func runFuzz(
    duration: Duration,
    coverageStrategy: CoverageStrategy,
    check: @escaping @Sendable (Expr) -> Bool?
) async -> SolveOutcome {
    let discards = OSAllocatedUnfairLock(initialState: 0)
    let probing = ProcessInfo.processInfo.environment["PTK_POOL_PROBE"] == "1"
    // (executed count, total wire length) — mean executed-term size.
    let execSize = OSAllocatedUnfairLock(initialState: (0, 0))
    let start = DispatchTime.now()
    func elapsed() -> UInt64 { DispatchTime.now().uptimeNanoseconds - start.uptimeNanoseconds }
    defer {
        if probing {
            let (n, total) = execSize.withLock { $0 }
            let line = ProbeCollector.shared.report(burstLength: 16)
                + " execTermWire mean=\(n == 0 ? 0 : total / n) n=\(n)\n"
            FileHandle.standardError.write(Data(line.utf8))
        }
    }

    do {
        let result = try await fuzz(
            duration: duration,
            persistence: .ephemeral,
            coverageStrategy: coverageStrategy,
            // PTK_SCHEDULER selects the pool configuration. The DEFAULT is
            // feature-ownership culling (matches PTK's flipped library default):
            // it bounds the pool to the smallest witness per feature, which on
            // shift_var_leq found the bug 20/20 at median 4.0s vs everyDiscovery's
            // 17/20 at 6.7s (a bloated pool of large terms mutates poorly).
            // "everydiscovery" restores the old keep-everything behavior;
            // "entropic" weights draws by rare-feature information gain;
            // "entropic-culled" composes both; "entropic-culled-burst" is now an
            // alias of "entropic-culled" (PTK's per-entry burst model was
            // superseded by the generation ratio); "boundary-culled" culls over
            // the cmp boundary-distance axis too. PTK_POOL_CAPACITY bounds pool
            // residence.
            scheduler: {
                let env = ProcessInfo.processInfo.environment
                let admission: PoolAdmission
                let base: @Sendable () -> [any PoolPlugin]
                switch env["PTK_SCHEDULER"] {
                case "culled":
                    admission = .featureOwnership; base = { [] }
                case "everydiscovery":
                    admission = .everyDiscovery; base = { [] }
                case "entropic":
                    admission = .everyDiscovery; base = { [EntropicWeightPolicy()] }
                case "entropic-culled":
                    admission = .featureOwnership; base = { [EntropicWeightPolicy()] }
                case "entropic-culled-burst":
                    // Alias of "entropic-culled": PTK's per-entry burst model was superseded by the generation ratio.
                    admission = .featureOwnership; base = { [EntropicWeightPolicy()] }
                case "boundary-culled":
                    // featureOwnership now culls over BOTH edges and cmp boundary
                    // distances (its BoundaryDistanceEvaluator is inert unless the
                    // strategy publishes distances), so the boundary axis is driven
                    // entirely by pairing this with a cmp strategy (e.g. ptk-boundary).
                    admission = .featureOwnership; base = { [] }
                default:
                    admission = .featureOwnership; base = { [] }
                }
                let probe = env["PTK_POOL_PROBE"] == "1"
                return MutationScheduler.weightedPool(
                    admission: admission,
                    policies: {
                        var policies = base()
                        if probe {
                            let p = PoolProbe()
                            ProbeCollector.shared.register(p)
                            policies.append(p)
                        }
                        return policies
                    },
                    capacity: env["PTK_POOL_CAPACITY"].flatMap(Int.init)
                )
            }(),
            parallelism: enginesParallelism,
            plugins: { [
                .stopOnFirstFailure(reason: .custom("counterexample_found")),
            ] }
        ) { (input: Expr) in
            if probing {
                let size = input.description.count
                execSize.withLock { $0 = ($0.0 + 1, $0.1 + size) }
            }
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

public enum SolveError: Error { case unknownProperty(String), unknownStrategy(String) }

/// The PTK coverage strategies this workload exposes as ETNA strategy names.
/// `ptk` stays as a back-compat alias for the default (`.pathTrie`).
public func coverageStrategy(named name: String) throws -> CoverageStrategy {
    switch name {
    case "ptk", "ptk-pathtrie":
        // PTK_PATHTRIE_VOCAB selects the culling vocabulary: "edges" opts out
        // of grams (pre-stage-4 behavior); an integer sets the gram length.
        switch ProcessInfo.processInfo.environment["PTK_PATHTRIE_VOCAB"] {
        case "edges": return .pathTrie(gramLength: nil)
        case let .some(v):
            guard let k = Int(v) else { return .pathTrie }
            return .pathTrie(gramLength: k)
        case nil: return .pathTrie
        }
    case "ptk-signaturematch": return .signatureMatch
    case "ptk-newedge": return .newEdge
    case "ptk-hitcountbuckets": return .hitCountBuckets
    // Comparison channel (requires the STLC SUT built with EmitCmpTrace).
    case "ptk-boundary": return .boundaryDistance
    // Composed: pathTrie edge novelty UNIONED with the cmp boundary-distance
    // signal — the mix-and-match case under test.
    case "ptk-pathtrie-boundary": return .pathTrie.combined(with: .boundaryDistanceOnly)
    case "ptk-newedge-boundary": return .newEdge.combined(with: .boundaryDistanceOnly)
    default: throw SolveError.unknownStrategy(name)
    }
}

/// Coverage-guided solve: fuzz `property` for `duration` judging novelty with
/// `coverageStrategy`. The mutant under test is whichever marauder variant is
/// active in the compiled `STLC` module.
public func solve(
    property: String,
    duration: Duration,
    coverageStrategy: CoverageStrategy = .pathTrie
) async throws -> SolveOutcome {
    switch property {
    case "SinglePreserve":
        return await runFuzz(duration: duration, coverageStrategy: coverageStrategy, check: { prop_single_preserve($0) })
    case "MultiPreserve":
        return await runFuzz(duration: duration, coverageStrategy: coverageStrategy, check: { prop_multi_preserve($0) })
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
