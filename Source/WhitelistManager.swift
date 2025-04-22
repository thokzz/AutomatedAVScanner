import Foundation

class WhitelistManager {
    private let key = "whitelistedVolumeKeys"
    static let shared = WhitelistManager()
    private init() {}

    func isWhitelisted(volume: ExternalVolume) -> Bool {
        return getWhitelistedKeys().contains(compositeKey(for: volume))
    }

    func addToWhitelist(volume: ExternalVolume) {
        var keys = getWhitelistedKeys()
        keys.insert(compositeKey(for: volume))
        UserDefaults.standard.set(Array(keys), forKey: key)
    }

    func removeFromWhitelist(volume: ExternalVolume) {
        var keys = getWhitelistedKeys()
        keys.remove(compositeKey(for: volume))
        UserDefaults.standard.set(Array(keys), forKey: key)
    }

    private func compositeKey(for volume: ExternalVolume) -> String {
        return "\(volume.volumeUUID)-\(volume.name)"
    }

    private func getWhitelistedKeys() -> Set<String> {
        let array = UserDefaults.standard.array(forKey: key) as? [String] ?? []
        return Set(array)
    }
}
