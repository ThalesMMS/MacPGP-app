import Foundation

public enum Armor {
    public static func armored(_ data: Data, as type: PGPArmorType) throws -> String {
        try RNPBackend.armor(data, type: type)
    }

    public static func readArmored(_ string: String) throws -> Data {
        try RNPBackend.dearmor(string)
    }
}
