class InitializeStepMarker: MarkerBase {
    let step: String

    init(
        _ recorder: MarkerRecorder,
        key: String,
        step: String,
        context: MarkerContext = .initialize
    ) {
        self.step = step
        super.init(recorder, context: context, markerKey: key)
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
