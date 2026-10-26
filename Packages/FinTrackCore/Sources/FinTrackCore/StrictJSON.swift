import Foundation

/// Reject unknown object fields at every typed level. Dictionary keys remain
/// open by design (archival source fields), while their values are still typed.
public enum StrictJSON {
    public static func decode<T: Decodable>(_ type: T.Type, from data: Data) throws -> T {
        // Foundation's JSON strategies must also apply to top-level framed items.
        if type == Data.self || type == Date.self { return try JSONDecoder().decode(type, from: data) }
        return try JSONDecoder().decode(Box<T>.self, from: data).value
    }
    private struct Box<T: Decodable>: Decodable {
        let value: T
        init(from decoder: any Decoder) throws { value = try T(from: Checked(decoder)) }
    }
    private struct AnyKey: CodingKey {
        let stringValue: String; let intValue: Int?
        init(stringValue: String) { self.stringValue = stringValue; intValue = Int(stringValue) }
        init(intValue: Int) { self.intValue = intValue; stringValue = String(intValue) }
    }
    private struct Checked: Decoder {
        let base: any Decoder
        init(_ base: any Decoder) { self.base = base }
        var codingPath: [any CodingKey] { base.codingPath }
        var userInfo: [CodingUserInfoKey: Any] { base.userInfo }
        func container<Key: CodingKey>(keyedBy type: Key.Type) throws -> KeyedDecodingContainer<Key> {
            let keys = try base.container(keyedBy: AnyKey.self).allKeys
            for key in keys where Key(stringValue: key.stringValue) == nil {
                throw ExchangeError.invalid("Unsupported field at " + (codingPath.map(\.stringValue) + [key.stringValue]).joined(separator: "."))
            }
            return KeyedDecodingContainer(Keys(base: try base.container(keyedBy: type)))
        }
        func unkeyedContainer() throws -> any UnkeyedDecodingContainer { Items(base: try base.unkeyedContainer()) }
        func singleValueContainer() throws -> any SingleValueDecodingContainer { try base.singleValueContainer() }
    }
    private struct Keys<Key: CodingKey>: KeyedDecodingContainerProtocol {
        let base: KeyedDecodingContainer<Key>
        var codingPath: [any CodingKey] { base.codingPath }
        var allKeys: [Key] { base.allKeys }
        func contains(_ key: Key) -> Bool { base.contains(key) }
        func decodeNil(forKey key: Key) throws -> Bool { try base.decodeNil(forKey: key) }
        func decode<T: Decodable>(_ type: T.Type, forKey key: Key) throws -> T {
            if type == Data.self || type == Date.self { return try base.decode(type, forKey: key) }
            return try T(from: Checked(base.superDecoder(forKey: key)))
        }
        func nestedContainer<NestedKey: CodingKey>(keyedBy type: NestedKey.Type, forKey key: Key) throws -> KeyedDecodingContainer<NestedKey> { try Checked(base.superDecoder(forKey: key)).container(keyedBy: type) }
        func nestedUnkeyedContainer(forKey key: Key) throws -> any UnkeyedDecodingContainer { try Checked(base.superDecoder(forKey: key)).unkeyedContainer() }
        func superDecoder() throws -> any Decoder { Checked(try base.superDecoder()) }
        func superDecoder(forKey key: Key) throws -> any Decoder { Checked(try base.superDecoder(forKey: key)) }
    }
    private struct Items: UnkeyedDecodingContainer {
        var base: any UnkeyedDecodingContainer
        var codingPath: [any CodingKey] { base.codingPath }
        var count: Int? { base.count }
        var isAtEnd: Bool { base.isAtEnd }
        var currentIndex: Int { base.currentIndex }
        mutating func decodeNil() throws -> Bool { try base.decodeNil() }
        mutating func decode<T: Decodable>(_ type: T.Type) throws -> T {
            if type == Data.self || type == Date.self { return try base.decode(type) }
            return try T(from: Checked(base.superDecoder()))
        }
        mutating func nestedContainer<NestedKey: CodingKey>(keyedBy type: NestedKey.Type) throws -> KeyedDecodingContainer<NestedKey> { try Checked(base.superDecoder()).container(keyedBy: type) }
        mutating func nestedUnkeyedContainer() throws -> any UnkeyedDecodingContainer { try Checked(base.superDecoder()).unkeyedContainer() }
        mutating func superDecoder() throws -> any Decoder { Checked(try base.superDecoder()) }
    }
}
