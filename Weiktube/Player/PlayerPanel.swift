// SPDX-License-Identifier: GPL-3.0-only
import MediaPlayer
import SwiftUI

struct PlayerPanel: View {
    @ObservedObject var player: PlayerCoordinator
    @ObservedObject var sponsor: SponsorBlockService
    @ObservedObject var dislikes: ReturnDislikeService
    let miniWidth: CGFloat
    let logicalSize: CGSize
    var onActions: () -> Void
    @State private var sliderPosition = 0.0
    @State private var scrubbing = false
    @State private var scrubIdentity = ""
    @State private var showRates = false
    @State private var captions = false
    @State private var controlsHeight: CGFloat = 100
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        VStack(spacing:0) {
            ZStack {
                PlaybackSurface(coordinator:player,logicalSize:logicalSize,miniWidth:miniWidth)
                if let error=player.errorMessage {
                    VStack(spacing:10) {
                        Text(error).font(.subheadline).multilineTextAlignment(.center)
                        Button("Erneut laden"){player.retry()}.buttonStyle(.borderedProminent)
                    }.padding(16).background(.regularMaterial,in:RoundedRectangle(cornerRadius:12)).padding(16)
                } else if !player.snapshot.ready {
                    ProgressView().tint(.white).padding(12).background(.black.opacity(0.65),in:Capsule()).allowsHitTesting(false)
                }
                if player.isMini {
                    Color.clear.contentShape(Rectangle()).onTapGesture { player.expand() }
                        .accessibilityElement().accessibilityLabel("Player vergrößern").accessibilityAddTraits(.isButton)
                        .accessibilityAction { player.expand() }
                    VStack {
                        HStack {
                            miniButton(player.snapshot.playing ? "pause.fill" : "play.fill", player.snapshot.playing ? "Pause" : "Abspielen") { player.togglePlayback() }
                            Spacer()
                            miniButton("xmark", "Player schließen") { player.close() }
                        }
                        Spacer(minLength:0)
                        GeometryReader { geometry in
                            Rectangle().fill(Color.weiktubeRed).frame(width:geometry.size.width * player.snapshot.progress,height:2)
                        }.frame(height:2)
                    }
                } else {
                    VStack {
                        HStack {
                            IconButton(icon:"chevron.down",label:"Player verkleinern") { player.minimize() }
                            Spacer()
                            if let url = player.route?.url { ShareLink(item:url) { Image(systemName:"square.and.arrow.up").frame(width:44,height:44) }.accessibilityLabel("Video teilen") }
                            IconButton(icon:"xmark",label:"Player schließen") { player.close() }
                        }.foregroundStyle(.white).background(LinearGradient(colors:[.black.opacity(0.7),.clear],startPoint:.top,endPoint:.bottom))
                        Spacer(minLength:0)
                        if let feedback = player.feedback {
                            Text(feedback).font(.headline).padding(.horizontal,16).padding(.vertical,10).background(.black.opacity(0.8),in:Capsule()).foregroundStyle(.white).accessibilityAddTraits(.updatesFrequently)
                        }
                        if player.snapshot.autoplayBlocked {
                            Button { player.play() } label: { Label("Tippen zum Abspielen",systemImage:"play.fill") }
                                .buttonStyle(.borderedProminent).tint(.weiktubeAccent).padding(8)
                        }
                        if player.showVolume {
                            HStack {
                                Image(systemName:"speaker.wave.2.fill")
                                SystemVolumeControl().frame(height:32)
                                Button { player.showVolume = false } label:{Image(systemName:"xmark").frame(width:44,height:44)}.accessibilityLabel("Lautstärkeregler schließen")
                            }.padding(.horizontal,12).background(.regularMaterial,in:RoundedRectangle(cornerRadius:12)).padding(12)
                        }
                        Spacer(minLength:0)
                    }
                    .allowsHitTesting(true)
                }
            }
            .frame(maxWidth:.infinity,maxHeight:.infinity)
            .clipped()
            controls
                .fixedSize(horizontal:false,vertical:true)
                .background(GeometryReader { geometry in Color.clear.preference(key:PlayerControlsHeight.self,value:geometry.size.height) })
                .frame(height:player.isMini ? 0:controlsHeight,alignment:.top)
                .opacity(player.isMini ? 0:1).clipped().allowsHitTesting(!player.isMini)
                .animation(reduceMotion ? nil:.easeInOut(duration:0.18),value:player.presentation.mode)
        }
        .background(.black)
        .clipShape(RoundedRectangle(cornerRadius:player.isMini ? 12:0))
        .shadow(color:.black.opacity(player.isMini ? 0.35:0),radius:8,y:4)
        .confirmationDialog("Wiedergabegeschwindigkeit",isPresented:$showRates,titleVisibility:.visible) {
            ForEach([0.5,0.75,1,1.25,1.5,1.75,2,2.5,3],id:\.self) { speed in
                Button("\(speed.formatted())×") { player.setRate(speed) }
            }
        }
        .confirmationDialog("Untertitel",isPresented:$captions,titleVisibility:.visible) {
            Button("Aus") { player.native.setCaption(language:nil) }
            ForEach(player.native.captions,id:\.0) { language in Button(language.1) { player.native.setCaption(language:language.0) } }
        }
        .accessibilityIdentifier("player.panel")
        .onPreferenceChange(PlayerControlsHeight.self) { if $0 > 0 { controlsHeight=$0 } }
    }
    private var controls: some View {
        VStack(spacing:4) {
            if player.isNative {Text(player.snapshot.title).font(.headline).lineLimit(2).frame(maxWidth:.infinity,alignment:.leading).padding(.horizontal,12).padding(.top,8)}
            if player.resumedAt > 0 {
                HStack {
                    Text("An letzter Stelle fortgesetzt · \(time(player.resumedAt))").font(.caption)
                    Spacer()
                    Button("Von vorne") { player.restart() }.font(.caption.weight(.semibold))
                }.padding(.horizontal,12)
            }
            ZStack {
                SponsorMarkersView(segments:sponsor.segments,duration:player.snapshot.duration,settings:sponsor.settings)
                    .frame(height:3).padding(.horizontal,2).offset(y: 7).allowsHitTesting(false)
                SeekTimeline(value:$sliderPosition,duration:player.snapshot.duration,identity:timelineIdentity,
                             enabled:player.snapshot.seekable && !player.isMini && !player.isPiP,onEditingChanged:{ editing in
                    if editing {scrubbing=true;scrubIdentity=timelineIdentity}
                    else {
                        let mayCommit=scrubbing && scrubIdentity==timelineIdentity
                        scrubbing=false;scrubIdentity=""
                        if mayCommit {player.seek(sliderPosition)}
                    }
                },onEditingCancelled:{cancelScrub()})
                    .accessibilityLabel("Wiedergabeposition").accessibilityValue("\(time(sliderPosition)) von \(time(player.snapshot.duration))")
            }.padding(.horizontal,12)
            HStack(spacing:0) {
                IconButton(icon:player.snapshot.playing ? "pause.fill":"play.fill",label:player.snapshot.playing ? "Pause":"Abspielen") { player.togglePlayback() }
                Text("\(time(scrubbing ? sliderPosition:player.snapshot.position)) / \(time(player.snapshot.duration))").font(.caption.monospacedDigit()).lineLimit(1).minimumScaleFactor(0.6)
                Spacer(minLength:2)
                Menu {
                    Button("Geschwindigkeit: \(player.snapshot.rate.formatted())×") { showRates=true }
                    if player.isNative {
                        Button("Untertitel") { captions=true }
                    } else {
                        Button(player.showingOriginalControls ? "Kompakten Player anzeigen":"YouTube-Steuerung: Untertitel & Qualität") { player.showOriginalPlayerControls() }
                    }
                    Button("Zoom zurücksetzen") { player.setZoom(1) }
                    Button("Lautstärke") { player.showVolume=true }
                    Button("Video-Aktionen",action:onActions).disabled(player.route?.videoID == nil)
                } label:{ Image(systemName:"ellipsis").frame(width:44,height:44) }.accessibilityLabel("Player-Einstellungen")
                IconButton(icon:"pip",label:"Picture-in-Picture") { player.togglePiP() }
                IconButton(icon:player.isFullscreen ? "arrow.down.right.and.arrow.up.left":"arrow.up.left.and.arrow.down.right",label:player.isFullscreen ? "Vollbild verlassen":"Vollbild") { player.toggleFullscreen() }
                    .accessibilityIdentifier("player.fullscreen")
            }.padding(.horizontal,4)
            if let request = sponsor.manualPrompt {
                Button { player.skipSponsorManually() } label: { Label("\(request.category.title) überspringen",systemImage:"forward.end") }.buttonStyle(.bordered).padding(.bottom,4)
            }
            if let notice = sponsor.notice, sponsor.settings.notices {
                HStack {
                    Text("\(notice.category.title) übersprungen").font(.caption)
                    Button("Rückgängig") { player.undoSponsorSkip() }.font(.caption.weight(.semibold))
                }.padding(.bottom,4)
            }
            if dislikes.enabled, let count = dislikes.count {
                Label("\(count.formatted()) Dislikes · geschätzt (RYD)",systemImage:"hand.thumbsdown")
                    .font(.caption).foregroundStyle(.secondary).padding(.bottom,4)
            }
        }.foregroundStyle(.white).background(Color(hex:0x0F0F0F))
        .onChange(of:player.snapshot.position) { _,newValue in if !scrubbing { sliderPosition=newValue } }
        .onChange(of:player.route?.url) { _,_ in
            cancelScrub();showRates=false;captions=false
        }
        .onChange(of:timelineIdentity) {_,_ in cancelScrub()}
        .onAppear { sliderPosition=max(0,player.snapshot.position) }
        .onDisappear {cancelScrub()}
    }
    private var timelineIdentity:String {"\(player.generation)|\(player.snapshot.elementID)"}
    private func cancelScrub() {scrubbing=false;scrubIdentity="";sliderPosition=max(0,player.snapshot.position)}
    private func miniButton(_ icon:String,_ label:String,action:@escaping ()->Void)->some View {
        Button(action:action) { Image(systemName:icon).font(.system(size:14,weight:.bold)).frame(width:32,height:32).background(.black.opacity(0.65),in:Circle()).frame(width:48,height:48) }.foregroundStyle(.white).accessibilityLabel(label)
    }
    private func time(_ value:Double)->String {
        guard value.isFinite,value>0 else{return "0:00"}
        let seconds=min(86400,Int(value))
        return seconds>=3600 ? String(format:"%d:%02d:%02d",seconds/3600,(seconds%3600)/60,seconds%60):String(format:"%d:%02d",seconds/60,seconds%60)
    }
}
private struct PlayerControlsHeight:PreferenceKey {
    static let defaultValue:CGFloat=100
    static func reduce(value:inout CGFloat,nextValue:()->CGFloat){value=nextValue()}
}
struct SystemVolumeControl:UIViewRepresentable {
    func makeUIView(context:Context)->MPVolumeView { let view=MPVolumeView();view.showsRouteButton=false;view.accessibilityLabel="Systemlautstärke";return view }
    func updateUIView(_ view:MPVolumeView,context:Context){}
}
