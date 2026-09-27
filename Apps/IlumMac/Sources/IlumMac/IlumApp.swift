#if canImport(SwiftUI)
import SwiftUI

@main
struct IlumApp: App {
    @StateObject private var model = IlumAppModel()
    var body: some Scene {
        WindowGroup("Ilum") {
            ContentView().environmentObject(model).frame(minWidth: 760, minHeight: 560)
        }
    }
}
#else
import Foundation
@main enum IlumUnsupportedPlatform {
    static func main() { print("IlumMac requires macOS with SwiftUI.") }
}
#endif
