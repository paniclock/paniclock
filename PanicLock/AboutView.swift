import SwiftUI

struct AboutView: View {
    private var appVersion: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0"
    }
    
    private var buildNumber: String {
        Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "1"
    }
    
    private var copyrightYear: String {
        let year = Calendar.current.component(.year, from: Date())
        return String(year)
    }
    
    var body: some View {
        VStack(spacing: 16) {
            // App Icon
            if let appIcon = NSApp.applicationIconImage {
                Image(nsImage: appIcon)
                    .resizable()
                    .scaledToFit()
                    .frame(width: 128, height: 128)
            }
            
            // App Name
            Text("PanicLock")
                .font(.system(size: 24, weight: .bold))
            
            // Version
            Text("Version \(appVersion) (\(buildNumber))")
                .font(.subheadline)
                .foregroundColor(.secondary)
            
            // Description
            Text("Instantly disable Touch ID and lock your Mac")
                .font(.callout)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
            
            Divider()
                .padding(.horizontal, 40)
            
            // Website Link
            if let url = URL(string: "https://paniclock.github.io/") {
                Link(destination: url) {
                    HStack(spacing: 4) {
                        Image(systemName: "globe")
                        Text("paniclock.github.io")
                    }
                }
                .font(.callout)
            }
            
            Spacer()
            
            // Copyright
            Text("© \(copyrightYear) PanicLock")
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .padding(30)
        .frame(width: 300, height: 340)
    }
}

#Preview {
    AboutView()
}
