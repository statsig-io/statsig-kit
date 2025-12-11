class InitializeStepMarker: MarkerBase {
    let step: String

    init(_ recorder: MarkerAtomicDict, key: String, step: String) {
        self.step = step
        super.init(recorder, context: .initialize, markerKey: key)
    }

    func start() {
        super.start([
            "step": step
        ])
    }

    func end(success: Bool) {
        super.end([
            "step": step,
            "success": success,
        ])
    }
}
