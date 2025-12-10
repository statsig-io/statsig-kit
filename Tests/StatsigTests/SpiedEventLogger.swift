import Foundation
@testable import Statsig

class SpiedEventLogger: EventLogger {
    var timerInstances: [Timer] = []
    var timesFlushCalled = 0
    var timesShutdownCalled = 0

    override func start(flushInterval: Double = 60) {
        super.start(flushInterval: flushInterval)

        DispatchQueue.main.async {
            self.timerInstances.append(self.flushTimer!)
        }
    }

    override func flush(completion: (() -> Void)? = nil) {
        super.flush(completion: completion)
        timesFlushCalled += 1
    }

    override func stop(completion: (() -> Void)? = nil) {
        super.stop(completion: completion)
        timesShutdownCalled += 1
    }
}
