import Foundation

@testable import Statsig

func decodeFailedLogRequestStore(_ data: Data?) -> FailedLogRequestStoreData? {
    guard let data = data else {
        return nil
    }

    return FailedLogRequestStoreData.decode(data)
}

func decodeFailedLogRequestStore(
    storageAdapter: StorageAdapter = FileStorageAdapter(),
    sdkKey: String
)
    -> FailedLogRequestStoreData?
{
    switch storageAdapter.read(FailedLogRequestStore.storagePath(sdkKey: sdkKey)) {
    case .data(let data):
        return decodeFailedLogRequestStore(data)
    case .notFound, .error:
        return nil
    }
}

func readPersistedFailedRequests(
    storageAdapter: StorageAdapter = FileStorageAdapter(),
    sdkKey: String
) -> [FailedLogRequest] {
    decodeFailedLogRequestStore(
        storageAdapter: storageAdapter,
        sdkKey: sdkKey
    )?.requests ?? []
}
