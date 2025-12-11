import Foundation

extension StatsigClient {
    internal func subscribeToApplicationLifecycle() {
        let center = NotificationCenter.default

        center.addObserver(
            self,
            selector: #selector(appWillBackground),
            name: PlatformCompatibility.willResignActiveNotification,
            object: nil)

        center.addObserver(
            self,
            selector: #selector(appWillTerminate),
            name: PlatformCompatibility.willTerminateNotification,
            object: nil)

        center.addObserver(
            self,
            selector: #selector(appDidBecomeActive),
            name: PlatformCompatibility.didBecomeActiveNotification,
            object: nil)
    }

    internal func unsubscribeFromApplicationLifecycle() {
        NotificationCenter.default.removeObserver(self)
    }

    @objc private func appDidBecomeActive() {
        logger.start()
    }

    @objc private func appWillBackground() {
        DispatchQueue.global().async { [weak self] in
            guard let self = self else {
                return
            }

            if self.statsigOptions.shutdownOnBackground {
                self.logger.stop()
            } else {
                self.logger.flush()
            }
        }
    }

    @objc private func appWillTerminate() {
        logger.stop()
    }
}
