import Statsig
import SwiftUI
import UIKit

fileprivate func getRandomUser() -> StatsigUser {
    StatsigUser(userID: "user_\(Int.random(in: 1...100))")
}

struct ContentView: View {
    private static let sdkKey = Constants.CLIENT_SDK_KEY

    @State private var user = getRandomUser()

    var body: some View {
        ScrollView {
            VStack {
                Button {
                    user = getRandomUser()
                    Statsig.updateUserWithResult(user)
                } label: {
                    Text("Update User")
                }

                Text("UserID: \(user.userID ?? "")")

                ForEach(0..<1000, id: \.self) { i in
                    let value = Statsig.checkGate("a_gate")
                    Text("Gate \(i): \(value ? "On" : "Off")")
                }
            }
        }
        .onAppear {
            Statsig.initialize(sdkKey: Self.sdkKey, user: user)

            NotificationCenter.default
                .addObserver(
                    forName: UserDefaults.didChangeNotification, object: UserDefaults.standard,
                    queue: .main
                ) { _ in }
        }
    }

}

class ManyGatesSwiftUIViewController: UIViewController {

    override func viewDidLoad() {
        super.viewDidLoad()

        let hostingController = UIHostingController(rootView: ContentView())

        addChild(hostingController)
        view.addSubview(hostingController.view)
        hostingController.didMove(toParent: self)

        hostingController.view.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            hostingController.view.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            hostingController.view.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            hostingController.view.topAnchor.constraint(equalTo: view.topAnchor),
            hostingController.view.bottomAnchor.constraint(equalTo: view.bottomAnchor),
        ])
    }
}
