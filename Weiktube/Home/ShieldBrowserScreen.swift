// SPDX-License-Identifier: GPL-3.0-only
import SwiftUI
import WebKit

@MainActor
final class ShieldBrowserModel:NSObject,ObservableObject,WKNavigationDelegate {
    @Published var address="https://www.wikipedia.org/"
    @Published var status="Gib eine öffentliche HTTPS-Adresse ein."
    let view:WKWebView
    private let adBlock:AdBlockService
    private var prepared=false
    init(adBlock:AdBlockService) {
        self.adBlock=adBlock
        let config=WKWebViewConfiguration()
        config.websiteDataStore = .default()
        config.mediaTypesRequiringUserActionForPlayback = .all
        view=WKWebView(frame:.zero,configuration:config)
        super.init()
        view.navigationDelegate=self
        view.allowsBackForwardNavigationGestures=true
    }
    func open() async {
        guard let url=URL(string:address),Self.allowed(url) else{status="Bitte eine gültige HTTPS-Adresse ohne Zugangsdaten eingeben.";return}
        if !prepared {await adBlock.configure(controller:view.configuration.userContentController);prepared=true}
        await view.setAllMediaPlaybackSuspended(true)
        status="Wird geladen …"
        view.load(URLRequest(url:url,timeoutInterval:30))
    }
    static func allowed(_ url:URL)->Bool {
        guard url.scheme?.lowercased()=="https",url.user==nil,url.password==nil,(url.port==nil || url.port==443),
              let host=url.host?.lowercased(),host.contains("."),host.count<=253 else{return false}
        return !["localhost","127.0.0.1","0.0.0.0"].contains(host) && !host.hasSuffix(".local") && !host.hasSuffix(".localhost")
    }
    func webView(_ webView:WKWebView,decidePolicyFor navigationAction:WKNavigationAction,decisionHandler:@escaping(WKNavigationActionPolicy)->Void) {
        guard let url=navigationAction.request.url,Self.allowed(url),url.host != "accounts.google.com" else{
            status="Diese Navigation wird nicht unterstützt. Google-Anmeldung erfolgt über die native Kontoansicht."
            decisionHandler(.cancel);return
        }
        decisionHandler(.allow)
    }
    func webView(_ webView:WKWebView,didFinish navigation:WKNavigation!){
        address=webView.url?.absoluteString ?? address
        status=(adBlock.enabled ? "Werbeschutz gemäß deinen Filtereinstellungen aktiviert.":"Werbeschutz ist in den Einstellungen deaktiviert.")+" Medien bleiben in dieser Zusatzansicht pausiert."
    }
    func webView(_ webView:WKWebView,didFailProvisionalNavigation navigation:WKNavigation!,withError error:Error){if(error as NSError).code != NSURLErrorCancelled{status="Seite konnte nicht geladen werden."}}
}
struct ShieldBrowserScreen:View {
    @StateObject private var model:ShieldBrowserModel
    init(adBlock:AdBlockService){_model=StateObject(wrappedValue:ShieldBrowserModel(adBlock:adBlock))}
    var body:some View {
        VStack(spacing:10) {
            HStack {
                TextField("https://…",text:$model.address).keyboardType(.URL).textInputAutocapitalization(.never).autocorrectionDisabled().textFieldStyle(.roundedBorder).onSubmit{Task{await model.open()}}
                Button{Task{await model.open()}}label:{Image(systemName:"arrow.right").frame(width:44,height:44)}.accessibilityLabel("Webseite öffnen")
            }.padding(.horizontal,12)
            Text(model.status).font(.caption).foregroundStyle(.secondary).padding(.horizontal,12)
            ShieldBrowserSurface(view:model.view)
            HStack {
                Button("Zurück"){model.view.goBack()};Spacer();Button("Vor"){model.view.goForward()};Spacer();Button("Neu laden"){model.view.reload()}
            }.padding(12)
        }.navigationTitle("Geschützter Browser").navigationBarTitleDisplayMode(.inline)
    }
}
private struct ShieldBrowserSurface:UIViewRepresentable {
    let view:WKWebView
    func makeUIView(context:Context)->WKWebView{view}
    func updateUIView(_ view:WKWebView,context:Context){}
}
