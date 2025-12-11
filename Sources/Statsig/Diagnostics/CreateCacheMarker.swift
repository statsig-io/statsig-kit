import Foundation

enum CacheType: String {
    case file
    case provider
    case user_defaults
}

class CreateCacheMarker: InitializeStepMarker {

    init(_ recorder: MarkerAtomicDict, key: String) {
        super.init(recorder, key: key, step: "create_cache")
    }

    func start(type: CacheType) {
        super.start([
            "step": self.step,
            "cache_type": type,
        ])
    }
}
