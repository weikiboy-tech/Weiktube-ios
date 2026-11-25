// SPDX-License-Identifier: GPL-3.0-only
import SwiftUI
import WebKit

struct WebSurface: UIViewRepresentable {
    let session: WebSession
    func makeUIView(context: Context) -> WKWebView { session.webView }
    func updateUIView(_ view: WKWebView, context: Context) { }
    static func dismantleUIView(_ uiView: WKWebView, coordinator: ()) {
        // The session owns the view across navigation and view reconstruction.
    }
}

struct BrowserScreen: View {
    @ObservedObject var session: WebSession
    var body: some View {
        ZStack(alignment: .top) {
            WebSurface(session: session)
            if session.loading { ProgressView().padding(10).background(.regularMaterial, in: Capsule()).padding(8).accessibilityLabel("Seite wird geladen") }
            if let error = session.errorMessage {
                VStack(spacing: 12) {
                    Image(systemName: "wifi.exclamationmark").font(.largeTitle)
                    Text(error).multilineTextAlignment(.center)
                    Button("Erneut laden") { session.reload() }.buttonStyle(.borderedProminent)
                }.padding(24).frame(maxWidth: 420).background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16)).padding(.top, 40)
            }
        }
    }
}
