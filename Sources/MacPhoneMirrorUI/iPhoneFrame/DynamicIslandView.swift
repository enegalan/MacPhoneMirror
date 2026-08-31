import SwiftUI
import MacPhoneMirrorCore

public enum DynamicIslandState: Equatable {
    case compact
    case expandedMedia
    case expandedNotification(title: String, subtitle: String)
}

public struct DynamicIslandView: View {
    public let model: PhoneModel
    @State private var islandState: DynamicIslandState = .compact
    @State private var isHovered: Bool = false
    
    public init(model: PhoneModel) {
        self.model = model
    }
    
    public var body: some View {
        Group {
            switch model.cutoutStyle {
            case .dynamicIsland:
                dynamicIslandContent
            case .notch:
                notchContent
            case .none:
                EmptyView()
            }
        }
    }
    
    private var dynamicIslandContent: some View {
        ZStack {
            Capsule(style: .continuous)
                .fill(Color.black)
                .overlay(
                    Capsule(style: .continuous)
                        .stroke(Color.white.opacity(0.12), lineWidth: 0.5)
                )
            
            switch islandState {
            case .compact:
                HStack(spacing: 8) {
                    // TrueDepth Camera sensor dot
                    Circle()
                        .fill(Color(red: 0.08, green: 0.12, blue: 0.2))
                        .frame(width: 10, height: 10)
                        .overlay(Circle().fill(Color.blue.opacity(0.3)).frame(width: 4, height: 4))
                    
                    Spacer()
                    
                    // FaceID / Ambient light sensor
                    Circle()
                        .fill(Color(red: 0.05, green: 0.05, blue: 0.08))
                        .frame(width: 9, height: 9)
                }
                .padding(.horizontal, 10)
                
            case .expandedMedia:
                HStack(spacing: 10) {
                    Image(systemName: "music.note")
                        .foregroundColor(.pink)
                        .font(.system(size: 13, weight: .bold))
                    
                    VStack(alignment: .leading, spacing: 1) {
                        Text("Now Playing")
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundColor(.white)
                        Text("MacPhoneMirror Pro Audio")
                            .font(.system(size: 8))
                            .foregroundColor(.gray)
                    }
                    Spacer()
                    
                    Image(systemName: "waveform")
                        .foregroundColor(.green)
                        .font(.system(size: 13))
                }
                .padding(.horizontal, 14)
                
            case .expandedNotification(let title, let subtitle):
                HStack(spacing: 8) {
                    Image(systemName: "iphone.radiowaves.left.and.right")
                        .foregroundColor(.blue)
                    VStack(alignment: .leading, spacing: 1) {
                        Text(title)
                            .font(.system(size: 10, weight: .bold))
                            .foregroundColor(.white)
                        Text(subtitle)
                            .font(.system(size: 8))
                            .foregroundColor(.gray)
                    }
                    Spacer()
                }
                .padding(.horizontal, 12)
            }
        }
        .frame(
            width: islandState == .compact ? model.dynamicIslandSize.width : 220,
            height: islandState == .compact ? model.dynamicIslandSize.height : 48
        )
        .animation(.spring(response: 0.35, dampingFraction: 0.75), value: islandState)
        .onTapGesture {
            withAnimation {
                if case .compact = islandState {
                    islandState = .expandedMedia
                } else {
                    islandState = .compact
                }
            }
        }
    }
    
    private var notchContent: some View {
        ZStack(alignment: .top) {
            UnevenRoundedRectangle(
                bottomLeadingRadius: 18,
                bottomTrailingRadius: 18,
                style: .continuous
            )
            .fill(Color.black)
            .frame(width: 160, height: 32)
            
            // Speaker ear piece & Camera
            HStack(spacing: 12) {
                Capsule()
                    .fill(Color(white: 0.18))
                    .frame(width: 44, height: 4)
                
                Circle()
                    .fill(Color(red: 0.08, green: 0.12, blue: 0.2))
                    .frame(width: 10, height: 10)
            }
            .padding(.top, 8)
        }
    }
}
