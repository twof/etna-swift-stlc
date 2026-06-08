// S-expression decoding for ETNA's serialized input format. Unlike the tree
// workloads (which wrap several arguments in a tuple), an STLC input is a single
// term, so a witness string parses directly to one `Expr`:
//   typ  := "TBool" | "(TBool)" | "(TFun" <typ> <typ> ")"
//   bool := "#t" | "#f"
//   expr := "(Var" <int> ")" | "(Bool" <bool> ")"
//         | "(Abs" <typ> <expr> ")" | "(App" <expr> <expr> ")"
// e.g. `(Abs TBool (App (Abs TBool (Var 1)) (Bool #t)))`. The decoder accepts
// both the bare `TBool` spelling the canonical witnesses use and the
// parenthesized `(TBool)` the Rust port's `Display` emits.

public enum SExpr: Equatable {
    case atom(String)
    case list([SExpr])
}

public enum DecodeError: Error, CustomStringConvertible {
    case malformed(String)

    public var description: String {
        switch self {
        case let .malformed(m): return "malformed S-expr: \(m)"
        }
    }
}

private func tokenize(_ s: String) -> [String] {
    var tokens: [String] = []
    var current = ""
    func flush() {
        if !current.isEmpty {
            tokens.append(current)
            current = ""
        }
    }
    for ch in s {
        switch ch {
        case "(", ")":
            flush()
            tokens.append(String(ch))
        case " ", "\t", "\n", "\r":
            flush()
        default:
            current.append(ch)
        }
    }
    flush()
    return tokens
}

private func parse(_ tokens: inout ArraySlice<String>) throws -> SExpr {
    guard let head = tokens.first else {
        throw DecodeError.malformed("unexpected end of input")
    }
    tokens = tokens.dropFirst()
    switch head {
    case "(":
        var elements: [SExpr] = []
        while let next = tokens.first, next != ")" {
            elements.append(try parse(&tokens))
        }
        guard tokens.first == ")" else {
            throw DecodeError.malformed("missing closing paren")
        }
        tokens = tokens.dropFirst()
        return .list(elements)
    case ")":
        throw DecodeError.malformed("unexpected closing paren")
    default:
        return .atom(head)
    }
}

public func parseSExpr(_ s: String) throws -> SExpr {
    var tokens = tokenize(s)[...]
    let result = try parse(&tokens)
    guard tokens.isEmpty else {
        throw DecodeError.malformed("trailing tokens: \(Array(tokens))")
    }
    return result
}

// MARK: - Typed decoders

public func decodeInt(_ e: SExpr) throws -> Int {
    guard case let .atom(s) = e, let n = Int(s) else {
        throw DecodeError.malformed("not an int: \(e)")
    }
    return n
}

public func decodeBool(_ e: SExpr) throws -> Bool {
    switch e {
    case .atom("#t"): return true
    case .atom("#f"): return false
    default: throw DecodeError.malformed("not a bool literal: \(e)")
    }
}

public func decodeTyp(_ e: SExpr) throws -> Typ {
    switch e {
    case .atom("TBool"), .list([.atom("TBool")]):
        return .TBool
    case let .list(items):
        guard items.count == 3, items[0] == .atom("TFun") else {
            throw DecodeError.malformed("not a type: \(e)")
        }
        return .TFun(try decodeTyp(items[1]), try decodeTyp(items[2]))
    default:
        throw DecodeError.malformed("not a type: \(e)")
    }
}

public func decodeExpr(_ e: SExpr) throws -> Expr {
    guard case let .list(items) = e, let first = items.first, case let .atom(tag) = first else {
        throw DecodeError.malformed("not an expr: \(e)")
    }
    switch tag {
    case "Var":
        guard items.count == 2 else { throw DecodeError.malformed("Var arity: \(e)") }
        return .Var(try decodeInt(items[1]))
    case "Bool":
        guard items.count == 2 else { throw DecodeError.malformed("Bool arity: \(e)") }
        return .Bool(try decodeBool(items[1]))
    case "Abs":
        guard items.count == 3 else { throw DecodeError.malformed("Abs arity: \(e)") }
        return .Abs(try decodeTyp(items[1]), try decodeExpr(items[2]))
    case "App":
        guard items.count == 3 else { throw DecodeError.malformed("App arity: \(e)") }
        return .App(try decodeExpr(items[1]), try decodeExpr(items[2]))
    default:
        throw DecodeError.malformed("unknown expr tag: \(tag)")
    }
}

// MARK: - Property dispatch

/// Evaluate a named property against a single serialized term.
/// Returns `nil` when the input is discarded (ill-typed).
public func evaluate(property: String, input: String) throws -> Bool? {
    let e = try decodeExpr(parseSExpr(input))
    switch property {
    case "SinglePreserve":
        return prop_single_preserve(e)
    case "MultiPreserve":
        return prop_multi_preserve(e)
    default:
        throw DecodeError.malformed("unknown property: \(property)")
    }
}
