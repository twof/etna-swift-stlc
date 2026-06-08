import STLCGen
import Foundation

// ETNA sample runner (cross-language `sample` capability).
//   stlc-sampler <property> <count>
// Emits a JSON array of {"time","value"} — generation time and the ETNA wire
// serialization of each generated term. Open-loop (no coverage feedback).

let args = CommandLine.arguments
guard args.count >= 3, let count = Int(args[2]) else {
    FileHandle.standardError.write(Data("usage: stlc-sampler <property> <count>\n".utf8))
    exit(2)
}
let property = args[1]

func esc(_ s: String) -> String {
    s.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\"")
}

do {
    let samples = try sample(property: property, count: count)
    let items = samples.map { "{\"time\":\"\($0.timeNs)ns\",\"value\":\"\(esc($0.wire))\"}" }
    print("[\(items.joined(separator: ","))]")
} catch {
    FileHandle.standardError.write(Data("sampler error: \(error)\n".utf8))
    exit(1)
}
