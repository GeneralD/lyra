extension KeyedDecodingContainer {
    /// Decodes a Double that may be encoded as Int in TOML
    func flexibleDouble(forKey key: Key) throws -> Double? {
        guard contains(key) else { return nil }
        if let d = try? decodeIfPresent(Double.self, forKey: key) { return d }
        if let i = try? decodeIfPresent(Int.self, forKey: key) { return Double(i) }
        return nil
    }

    func flexibleDoubleRequired(forKey key: Key) throws -> Double {
        if let d = try? decode(Double.self, forKey: key) { return d }
        return Double(try decode(Int.self, forKey: key))
    }
}
