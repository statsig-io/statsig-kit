import Statsig
import UIKit

class ManyUpdatesViewController: UIViewController {

    var queues: [DispatchQueue] = []

    override func viewDidLoad() {
        super.viewDidLoad()

        view.backgroundColor = UIColor.white

        let user = StatsigUser(userID: "a-user")
        let opts = StatsigOptions(enableCacheByFile: true)

        Statsig.initialize(
            sdkKey: Constants.CLIENT_SDK_KEY,
            user: user,
            options: opts
        ) { [weak self] err in
            if let err = err {
                print("Error \(err.message)")
            }

            self?.addButton()
        }
    }

    private func addButton() {
        let button = UIButton(type: .system)
        button.frame = CGRect(x: 100, y: 100, width: 200, height: 50)
        button.setTitle("Tap", for: .normal)
        button.addTarget(self, action: #selector(runUpdates), for: .touchUpInside)
        view.addSubview(button)
    }

    @objc private func runUpdates() {
        let numberOfTasks = 10

        if queues.isEmpty {
            for i in 0..<numberOfTasks {
                queues.append(DispatchQueue(label: "com.statsig.task_\(i)"))
            }
        }

        for i in 0..<numberOfTasks {
            let queue = queues[i]

            queue.async {
                let user = self.getRandomUser()
                print("Updating user \(user.userID ?? "")...")
                Statsig.updateUserWithResult(user) { err in
                    print("Updated user \(user.userID ?? "")")
                    print("Gate check \(Statsig.checkGate("partial_gate"))")
                }
            }
        }
    }

    private func getRandomUser() -> StatsigUser {
        StatsigUser(userID: "user_\(Int.random(in: 1...100))")
    }
}
