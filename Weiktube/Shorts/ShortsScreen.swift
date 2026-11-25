// SPDX-License-Identifier: GPL-3.0-only
import SwiftUI

@MainActor
struct ShortsScreen:View {
    @ObservedObject var session:WebSession
    @State private var scrubValue=0.0
    @State private var scrubbing=false
    @State private var scrubIdentity=""
    var body:some View {
        VStack(spacing:0) {
            ZStack(alignment:.bottomTrailing) {
                BrowserScreen(session:session)
                Button {
                    let muted = !session.snapshot.muted
                    Task { await session.setUserMuted(muted) }
                } label: {
                    Image(systemName:session.snapshot.muted ? "speaker.slash.fill":"speaker.wave.2.fill")
                        .font(.title3).padding(14).background(.black.opacity(0.7),in:Circle()).foregroundStyle(.white)
                }.padding(16).accessibilityLabel(session.snapshot.muted ? "Ton einschalten":"Stummschalten")
            }
            if session.snapshot.ready {
                HStack(spacing:8) {
                    Button {
                        let command=session.snapshot.playing ? "pause":"play"
                        send(command,elementID:session.snapshot.elementID)
                    } label:{Image(systemName:session.snapshot.playing ? "pause.fill":"play.fill").frame(width:44,height:44)}
                        .accessibilityLabel(session.snapshot.playing ? "Short pausieren":"Short abspielen")
                    SeekTimeline(value:$scrubValue,duration:session.snapshot.duration,identity:timelineIdentity,
                                 enabled:session.snapshot.seekable,onEditingChanged:{ editing in
                        if editing {scrubbing=true;scrubIdentity=timelineIdentity}
                        else {
                            let mayCommit=scrubbing && scrubIdentity==timelineIdentity
                            scrubbing=false;scrubIdentity=""
                            if mayCommit {send("seek",values:["seconds":scrubValue],elementID:session.snapshot.elementID)}
                        }
                    },onEditingCancelled:{cancelScrub()})
                        .accessibilityLabel("Short vorspulen").accessibilityValue(PlaybackTimeFormatter.string(scrubValue))
                    Text(PlaybackTimeFormatter.string(session.snapshot.duration)).font(.caption.monospacedDigit()).padding(.trailing,12)
                }.background(Color(hex:0x0F0F0F)).foregroundStyle(.white)
            }
            if session.snapshot.autoplayBlocked {
                Button("Tippen für Wiedergabe mit Ton") {
                    let generation=session.generation,identity=session.snapshot.elementID
                    Task {
                        guard generation==session.generation else{return}
                        await session.setUserMuted(false)
                        guard generation==session.generation,identity==session.snapshot.elementID else{return}
                        _=await session.command("play",elementID:identity)
                    }
                }.buttonStyle(.borderedProminent).padding(8)
            }
        }
        .onChange(of:session.snapshot.position) { _,value in if !scrubbing {scrubValue=value} }
        .onChange(of:timelineIdentity) { _,_ in cancelScrub() }
        .onDisappear {cancelScrub()}
        .accessibilityIdentifier("shorts.screen")
    }
    private func send(_ name:String,values:[String:Any]=[:],elementID:String) {
        let generation=session.generation,videoID=session.snapshot.videoID
        Task {
            guard generation==session.generation,elementID==session.snapshot.elementID,videoID==session.snapshot.videoID else{return}
            _=await session.command(name,values:values,elementID:elementID)
        }
    }
    private var timelineIdentity:String {"\(session.generation)|\(session.snapshot.elementID)|\(session.snapshot.videoID)"}
    private func cancelScrub() {scrubbing=false;scrubIdentity="";scrubValue=session.snapshot.position}
}
