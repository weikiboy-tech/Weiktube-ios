// SPDX-License-Identifier: GPL-3.0-only
import Foundation
import SwiftUI
import UIKit
import UniformTypeIdentifiers

@MainActor
final class ShareViewController:UIViewController {
    private let model=ShareImportModel()
    override func viewDidLoad() {
        super.viewDidLoad()
        let host=UIHostingController(rootView:ShareImportView(model:model,onSave:{[weak self] in self?.save()},onCancel:{[weak self] in self?.finish()}))
        addChild(host)
        host.view.translatesAutoresizingMaskIntoConstraints=false
        view.addSubview(host.view)
        NSLayoutConstraint.activate([
            host.view.leadingAnchor.constraint(equalTo:view.leadingAnchor),host.view.trailingAnchor.constraint(equalTo:view.trailingAnchor),
            host.view.topAnchor.constraint(equalTo:view.topAnchor),host.view.bottomAnchor.constraint(equalTo:view.bottomAnchor)
        ])
        host.didMove(toParent:self)
        model.load(items:extensionContext?.inputItems.compactMap{$0 as? NSExtensionItem} ?? [])
    }
    private func save() {
        model.save()
    }
    private func finish() {model.cancel();extensionContext?.completeRequest(returningItems:nil)}
    override func viewDidDisappear(_ animated:Bool) {
        super.viewDidDisappear(animated)
        if isBeingDismissed || navigationController?.isBeingDismissed == true {model.cancel()}
    }
}

@MainActor
private final class ShareImportModel:ObservableObject {
    @Published var route:MediaRoute?
    @Published var status="Link wird geprüft …"
    @Published var loading=true
    @Published var saving=false
    @Published var saved=false
    private var task:Task<Void,Never>?
    private var revision=UUID()
    func cancel() {revision=UUID();task?.cancel();task=nil}
    func load(items:[NSExtensionItem]) {
        cancel()
        let expected=revision
        route=nil;loading=true;saved=false
        task=Task { [weak self] in
            let providers=items.prefix(10).flatMap{$0.attachments ?? []}.prefix(20)
            for provider in providers {
                guard !Task.isCancelled else{return}
                let type:String?
                if provider.hasItemConformingToTypeIdentifier(UTType.url.identifier) {type=UTType.url.identifier}
                else if provider.hasItemConformingToTypeIdentifier(UTType.plainText.identifier) {type=UTType.plainText.identifier}
                else {type=nil}
                guard let type else{continue}
                do {
                    let text:String?=try await withCheckedThrowingContinuation { continuation in
                        provider.loadItem(forTypeIdentifier:type,options:nil) { item,error in
                            if let error {continuation.resume(throwing:error);return}
                            if let url=item as? URL {continuation.resume(returning:url.absoluteString)}
                            else if let text=item as? String {continuation.resume(returning:text)}
                            else {continuation.resume(returning:nil)}
                        }
                    }
                    guard !Task.isCancelled,let self,self.revision==expected else{return}
                    if let text,text.utf8.count<=16384,let valid=YouTubeLinkRouter.extractFirstRoute(from:text) {
                        self.route=valid;self.status="Bereit zum Speichern";self.loading=false;self.task=nil;return
                    }
                } catch {continue}
            }
            guard !Task.isCancelled,let self,self.revision==expected else{return}
            self.status="Kein unterstützter YouTube- oder öffentlicher HTTPS-Video-Link gefunden."
            self.loading=false;self.task=nil
        }
    }
    func save() {
        guard let route,!saving,!saved else{return};saving=true
        let expected=revision
        task=Task { [weak self] in
            do {
                let inbox=try SharedLinkInbox.configured()
                try await inbox.enqueue(route.url)
                guard !Task.isCancelled,let self,self.revision==expected else{return}
                self.saved=true;self.saving=false;self.task=nil
                self.status="Link gespeichert. Öffne Weiktube, um ihn abzuspielen."
                // The user dismisses this confirmation. Share extensions do not force-open the host app.
            } catch {
                guard !Task.isCancelled,let self,self.revision==expected else{return}
                self.saving=false;self.task=nil;self.status="Der Link konnte nicht vorgemerkt werden. Die gemeinsame App Group muss beim Signieren eingerichtet sein."
            }
        }
    }
}

@MainActor
private struct ShareImportView:View {
    @ObservedObject var model:ShareImportModel
    let onSave:()->Void
    let onCancel:()->Void
    var body:some View {
        NavigationStack {
            VStack(spacing:20) {
                Image(systemName:model.saved ? "checkmark.circle.fill":"play.rectangle.fill").font(.system(size:52)).foregroundStyle(Color(red:101/255,green:216/255,blue:200/255))
                Text(model.saved ? "In Weiktube gespeichert":"In Weiktube öffnen").font(.title2.bold())
                Text(model.status).multilineTextAlignment(.center)
                if let route=model.route {Text(route.url.absoluteString).font(.footnote).foregroundStyle(.secondary).lineLimit(3)}
                if model.loading || model.saving {ProgressView()}
                if model.route != nil && !model.saved {
                    Button("Für Weiktube vormerken",action:onSave).buttonStyle(.borderedProminent).disabled(model.saving)
                }
                if model.saved {Button("Fertig",action:onCancel).buttonStyle(.borderedProminent)}
                Spacer(minLength:0)
            }.padding(24).padding(.top,24)
                .navigationTitle("Weiktube").navigationBarTitleDisplayMode(.inline)
                .toolbar{ToolbarItem(placement:.cancellationAction){Button("Schließen",action:onCancel)}}
        }
    }
}
