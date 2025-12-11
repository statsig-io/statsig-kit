import Statsig
import UIKit

class BasicViewController: UIViewController {

    override func viewDidLoad() {
        super.viewDidLoad()

        let user = StatsigUser(
            userID: "a-user",
            custom: [
                "name": "jkw",
                "speed": 1.2,
                "verified": true,
                "visits": 3,
                "tags": ["cool", "rad", "neat"],
            ])

        Statsig.initialize(sdkKey: Constants.CLIENT_SDK_KEY, user: user) { err in
            if let err = err {
                print("Error \(err.message)")
            }

            let result = Statsig.checkGate("a_gate")
            print("Result: \(result == true ? "Pass": "Fail")")
            self.view.backgroundColor = result ? UIColor.systemGreen : UIColor.systemRed
        }
    }
}
