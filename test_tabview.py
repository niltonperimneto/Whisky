import subprocess

code = """
import SwiftUI

struct TestSettings: View {
    var body: some View {
        TabView {
            Text("General")
                .tabItem {
                    Label("General", systemImage: "gearshape")
                }
                .tag(0)
            Text("Advanced")
                .tabItem {
                    Label("Advanced", systemImage: "slider.horizontal.3")
                }
                .tag(1)
        }
        .frame(width: 520, height: 420)
    }
}
"""

with open("/tmp/TestSettings.swift", "w") as f:
    f.write(code)

res = subprocess.run(["swiftc", "-parse", "/tmp/TestSettings.swift"], capture_output=True, text=True)
print("Exit code:", res.returncode)
print(res.stderr)
