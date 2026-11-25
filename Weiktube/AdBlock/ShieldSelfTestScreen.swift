// SPDX-License-Identifier: GPL-3.0-only
import SwiftUI
import WebKit

/// A local deterministic fixture checks WebKit's blocking mechanism without third-party requests.
@MainActor
final class ShieldSelfTest: NSObject, ObservableObject, WKScriptMessageHandler {
    @Published private(set) var status = "Noch nicht ausgeführt"
    @Published private(set) var running = false
    @Published private(set) var webView: WKWebView?
    private var timeout: Task<Void,Never>?
    private var revision = 0
    func run() {
        guard !running else{return}
        revision += 1;let captured=revision
        running=true;status="Lokale WebKit-Prüfung läuft …"
        Task { [weak self] in
            guard let self else{return}
            do {
                let specification:[[String:Any]] = [
                    ["trigger":["url-filter":".*blocked\\.png$","resource-type":["image"]],"action":["type":"block"]],
                    ["trigger":["url-filter":".*"],"action":["type":"css-display-none","selector":"#fixture-ad"]]
                ]
                let source=String(data:try JSONSerialization.data(withJSONObject:specification),encoding:.utf8)!
                let rules:WKContentRuleList=try await withCheckedThrowingContinuation { continuation in
                    WKContentRuleListStore.default().compileContentRuleList(forIdentifier:"WeiktubeLocalSelfTest",encodedContentRuleList:source) { list,error in
                        if let list {continuation.resume(returning:list)}
                        else {continuation.resume(throwing:error ?? URLError(.cannotParseResponse))}
                    }
                }
                guard captured==revision else{return}
                let config=WKWebViewConfiguration()
                config.websiteDataStore = .nonPersistent()
                config.userContentController.add(SelfTestMessageHandler(owner:self),name:"fixtureResult")
                config.userContentController.add(rules)
                config.setURLSchemeHandler(LocalFilterFixture(),forURLScheme:"weiktube-fixture")
                config.mediaTypesRequiringUserActionForPlayback = .all
                let view=WKWebView(frame:.zero,configuration:config)
                webView=view
                view.load(URLRequest(url:URL(string:"weiktube-fixture://local/index.html")!))
                timeout=Task { [weak self] in
                    try? await Task.sleep(for:.seconds(8))
                    guard !Task.isCancelled,let self,captured==revision,running else{return}
                    finish("Keine auswertbare Antwort. Die Filterwirkung auf dieser WebKit-Version ist damit nicht bestätigt.")
                }
            } catch {
                guard captured==revision else{return}
                finish("Die lokalen Testregeln konnten nicht kompiliert werden.")
            }
        }
    }
    func userContentController(_ userContentController:WKUserContentController,didReceive message:WKScriptMessage) {
        guard running,message.frameInfo.isMainFrame,message.frameInfo.request.url?.scheme=="weiktube-fixture",
              let result=message.body as? [String:Bool],let control=result["control"],let blocked=result["blocked"],let cosmetic=result["cosmetic"] else{return}
        if control && blocked && cosmetic {
            finish("Bestanden: Kontrollbild geladen, Testbild blockiert, Test-Werbeelement ausgeblendet. Dies prüft die WebKit-Mechanik; keine Aussage über aktuelle YouTube-Werbung.")
        } else {
            finish("Nicht vollständig bestätigt: Kontrollbild \(control ? "geladen":"fehlgeschlagen"), Testbild \(blocked ? "blockiert":"nicht blockiert"), kosmetische Regel \(cosmetic ? "wirksam":"nicht bestätigt"). Keine vollständige Filterwirkung zugesagt.")
        }
    }
    private func finish(_ message:String) {
        status=message;running=false;timeout?.cancel();timeout=nil
        webView?.configuration.userContentController.removeScriptMessageHandler(forName:"fixtureResult")
    }
    func stop() {
        revision += 1;timeout?.cancel();timeout=nil
        webView?.stopLoading();webView?.configuration.userContentController.removeScriptMessageHandler(forName:"fixtureResult")
        webView=nil;running=false
    }
}
@MainActor
private final class SelfTestMessageHandler:NSObject,WKScriptMessageHandler {
    weak var owner:ShieldSelfTest?
    init(owner:ShieldSelfTest){self.owner=owner}
    func userContentController(_ userContentController:WKUserContentController,didReceive message:WKScriptMessage){owner?.userContentController(userContentController,didReceive:message)}
}

@MainActor
private final class LocalFilterFixture:NSObject,WKURLSchemeHandler {
    func webView(_ webView:WKWebView,start urlSchemeTask:WKURLSchemeTask) {
        guard let url=urlSchemeTask.request.url,url.scheme=="weiktube-fixture",url.host=="local" else {
            urlSchemeTask.didFailWithError(URLError(.unsupportedURL));return
        }
        let data:Data,mime:String
        if url.path=="/index.html" {
            let html="""
            <!doctype html><html><meta name="viewport" content="width=device-width"><body>
            <p>Lokale Filterprüfung</p><div id="fixture-ad">Test-Werbeelement</div>
            <script>
            (()=>{let count=0;const result={control:false,blocked:false,cosmetic:false};
            function report(){if(++count!==2)return;requestAnimationFrame(()=>{result.cosmetic=getComputedStyle(document.getElementById('fixture-ad')).display==='none';window.webkit.messageHandlers.fixtureResult.postMessage(result);});}
            const good=new Image();good.onload=()=>{result.control=true;report();};good.onerror=report;good.src='weiktube-fixture://local/allowed.png';
            const bad=new Image();bad.onload=report;bad.onerror=()=>{result.blocked=true;report();};bad.src='weiktube-fixture://local/blocked.png';
            })();</script></body></html>
            """
            data=Data(html.utf8);mime="text/html"
        } else if ["/allowed.png","/blocked.png"].contains(url.path) {
            data=Data(base64Encoded:"iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR4nGNIvXHiPwAGsAMFjD4r4QAAAABJRU5ErkJggg==")!;mime="image/png"
        } else {urlSchemeTask.didFailWithError(URLError(.fileDoesNotExist));return}
        urlSchemeTask.didReceive(URLResponse(url:url,mimeType:mime,expectedContentLength:data.count,textEncodingName:mime=="text/html" ? "utf-8":nil))
        urlSchemeTask.didReceive(data);urlSchemeTask.didFinish()
    }
    func webView(_ webView:WKWebView,stop urlSchemeTask:WKURLSchemeTask){}
}
struct ShieldSelfTestScreen:View {
    @StateObject private var model=ShieldSelfTest()
    var body:some View {
        VStack(alignment:.leading,spacing:20) {
            Label("Lokaler WebKit-Filtertest",systemImage:"checkmark.shield").font(.title2.bold())
            Text("Die Testseite wird vollständig in der App bereitgestellt. Ein Kontrollbild, ein gesperrtes Bild und eine kosmetische Regel werden getrennt geprüft.")
            Text(model.status).font(.subheadline).accessibilityIdentifier("shield.selftest.status")
            Button(model.running ? "Prüfung läuft …":"Test starten"){model.run()}.buttonStyle(.borderedProminent).disabled(model.running)
            if let view=model.webView {SelfTestWebSurface(view:view).frame(height:120).accessibilityHidden(true)}
            Spacer()
        }.padding(20).navigationTitle("Filtertest").onDisappear{model.stop()}
    }
}
private struct SelfTestWebSurface:UIViewRepresentable {
    let view:WKWebView
    func makeUIView(context:Context)->WKWebView{view}
    func updateUIView(_ view:WKWebView,context:Context){}
}
