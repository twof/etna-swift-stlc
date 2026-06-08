import STLC
import STLCGen
import Foundation

// ETNA solve runner (product name `stlc`).
//   stlc <strategy> <property> [duration_seconds]
// The mutant under test is whichever marauder variant is active in the compiled
// `STLC` module — ETNA's driver activates it (source-swap) and rebuilds before
// invoking this runner. No mutant is selected here.
//
// Prints one line of ETNA result JSON to stdout.

let args = CommandLine.arguments
guard args.count >= 3 else {
    FileHandle.standardError.write(Data("usage: stlc <strategy> <property> [duration_seconds]\n".utf8))
    FileHandle.standardError.write(Data("properties: \(stlcProperties.joined(separator: ", "))\n".utf8))
    exit(2)
}

let strategy = args[1]   // e.g. "ptk"; accepted and ignored (one strategy)
let property = args[2]
// ETNA passes its per-task `timeout` as the 3rd arg (e.g. "8" or "60.0"); we
// fuzz for that budget. ETNA hard-kills the process at `timeout`, so we shave a
// small margin to print before the kill on the (rare) no-counterexample path.
let timeoutSecs = args.count >= 4 ? (Double(args[3]) ?? 10) : 10
let durationSecs = max(timeoutSecs - 0.5, 0.5)

_ = strategy

do {
    let outcome = try await solve(property: property, duration: .seconds(durationSecs))
    print(outcome.json)
} catch {
    let aborted = SolveOutcome(status: "aborted", tests: 0, discards: 0,
                               counterexample: nil, error: "\(error)", timeNs: 0)
    print(aborted.json)
}
