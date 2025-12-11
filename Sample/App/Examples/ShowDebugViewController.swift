import Statsig
import UIKit

class ShowDebugViewController: UIViewController {

    var button: UIButton?

    override func viewDidLoad() {
        super.viewDidLoad()

        view.backgroundColor = UIColor.white

        let user = StatsigUser(
            userID: "a-user",
            custom: [
                "name": "jkw",
                "speed": 1.2,
                "verified": true,
                "visits": 3,
                "tags": ["cool", "rad", "neat"],
            ])

        Statsig.initialize(sdkKey: Constants.CLIENT_SDK_KEY, user: user) { [weak self] err in
            if let err = err {
                print("Error \(err.message)")
            }

            self?.addButton()
        }
    }

    private func addButton() {
        let button = UIButton(type: .system)
        button.frame = CGRect(x: 100, y: 100, width: 200, height: 50)
        button.setTitle("Show Debug View", for: .normal)
        button.addTarget(self, action: #selector(onShowDebugViewTouchUpInside), for: .touchUpInside)
        view.addSubview(button)
    }

    @objc func onShowDebugViewTouchUpInside() {
        Statsig.openDebugView { shouldReload in
            print("Debugger Closed - Should Reload: \(shouldReload)")
        }
    }
}
