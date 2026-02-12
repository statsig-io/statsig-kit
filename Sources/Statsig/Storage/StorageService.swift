// TODO: Migration

struct StorageService {

    // TODO: Delete this static variable once we ship multi-file storage
    internal static var useMultiFileStorage = false

    let sdkKey: String
    let userPayload: UserPayloadStore

    init(sdkKey: String) {
        self.sdkKey = sdkKey
        self.userPayload = UserPayloadStore(sdkKey: sdkKey)
    }

}
