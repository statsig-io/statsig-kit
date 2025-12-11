class DiagnosticsEvent: Event {
    let context: String
    let markers: [[String: Any]]

    init(
        _ user: StatsigUser,
        _ context: String,
        _ markers: [[String: Any]]
    ) {
        self.context = context
        self.markers = markers

        super.init(
            user: user,
            name: "statsig::diagnostics",
            disableCurrentVCLogging: true
        )
    }

    override func toDictionary() -> [String: Any] {
        var dict = super.toDictionary()
        dict["metadata"] = [
            "context": context,
            "markers": markers,
        ]
        return dict
    }
}
