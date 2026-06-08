import STLC
import Foundation

// Differential-oracle helper (mirrors the Rust reference's `diff_oracle` bin):
// read one term per line from stdin, print "<inferred type>\t<40-step normal
// form>" per line in canonical wire form. Running this and the Rust bin on the
// same corpus and diffing the output validates this port's `getTyp` + `shift` /
// `subst` / `substTop` / `pstep` against the independent reference.

while let line = readLine(strippingNewline: true) {
    let s = line.trimmingCharacters(in: .whitespaces)
    if s.isEmpty { continue }
    do {
        let e = try decodeExpr(parseSExpr(s))
        let ty = getTyp([], e).map { $0.description } ?? "ILL"
        let nf = multistep(40, pstep, e).map { $0.description } ?? "NONE"
        print("\(ty)\t\(nf)")
    } catch {
        print("PARSE_ERR\t\(error)")
    }
}
