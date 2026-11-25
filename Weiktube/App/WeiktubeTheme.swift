// SPDX-License-Identifier: GPL-3.0-only
import SwiftUI

extension Color {
    init(hex: UInt32) {
        self.init(.sRGB, red: Double((hex >> 16) & 255) / 255, green: Double((hex >> 8) & 255) / 255, blue: Double(hex & 255) / 255, opacity: 1)
    }
    static let weiktubeMint = Color(hex: 0x65D8C8)
    static let weiktubeRed = Color(hex: 0xFF0033)
    static let weiktubeBackground = Color(uiColor: UIColor { $0.userInterfaceStyle == .dark ? UIColor(red:15/255,green:15/255,blue:15/255,alpha:1) : .white })
    static let weiktubeCard = Color(uiColor: UIColor { $0.userInterfaceStyle == .dark ? UIColor(white:33/255,alpha:1) : UIColor(white:242/255,alpha:1) })
    static let weiktubeAccent = Color(uiColor: UIColor { $0.userInterfaceStyle == .dark ? UIColor(red:101/255,green:216/255,blue:200/255,alpha:1) : UIColor(red:0,green:107/255,blue:96/255,alpha:1) })
}

struct WeiktubeLogo: View {
    var body: some View {
        GeometryReader { geometry in
            ZStack {
                Color(hex: 0x10151D)
                Path { path in
                    let sx = geometry.size.width / 108, sy = geometry.size.height / 108
                    path.move(to: CGPoint(x:27*sx,y:28*sy));path.addLine(to:CGPoint(x:44*sx,y:38*sy));path.addLine(to:CGPoint(x:44*sx,y:70*sy));path.addLine(to:CGPoint(x:27*sx,y:80*sy));path.closeSubpath()
                    path.move(to:CGPoint(x:49*sx,y:28*sy));path.addLine(to:CGPoint(x:83*sx,y:54*sy));path.addLine(to:CGPoint(x:49*sx,y:80*sy));path.closeSubpath()
                }.fill(Color.weiktubeMint)
            }
        }.clipShape(RoundedRectangle(cornerRadius:6)).accessibilityLabel("Weiktube")
    }
}

struct IconButton: View {
    let icon: String
    let label: String
    var action: () -> Void
    var body: some View {
        Button(action: action) { Image(systemName: icon).font(.system(size:21,weight:.medium)).frame(minWidth:44,minHeight:44).contentShape(Rectangle()) }
            .buttonStyle(.plain).accessibilityLabel(label)
    }
}
