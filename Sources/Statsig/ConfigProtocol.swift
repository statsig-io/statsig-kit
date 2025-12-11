internal protocol ConfigProtocol {
    var isExperimentActive: Bool { get }
    var isUserInExperiment: Bool { get }
    var isDeviceBased: Bool { get }
    var rawValue: [String: Any] { get }
}
