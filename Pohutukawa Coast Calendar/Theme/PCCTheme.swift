import SwiftUI

enum PCCTheme {
    static let pohutukawaRed = Color(red: 0.78, green: 0.10, blue: 0.07)
    static let pohutukawaOrange = Color(red: 0.94, green: 0.36, blue: 0.10)
    static let leafGreen = Color(red: 0.12, green: 0.30, blue: 0.20)
    static let deepGreen = Color(red: 0.04, green: 0.12, blue: 0.10)
    static let cream = Color(red: 0.98, green: 0.95, blue: 0.88)
    static let sand = Color(red: 0.86, green: 0.76, blue: 0.60)
    static let ink = Color(red: 0.10, green: 0.13, blue: 0.12)

    static let cardRadius: CGFloat = 24
    static let smallRadius: CGFloat = 14

    static let screenTitle = Color.white
    static let screenSubtitle = Color.white.opacity(0.82)
    static let screenSectionTitle = Color.white.opacity(0.94)
    static let screenSectionFooter = Color.white.opacity(0.82)
    static let cardTitle = ink
    static let cardBody = ink.opacity(0.68)
    static let cardMeta = ink.opacity(0.58)
}

enum PCCWallpaperStyle: String, CaseIterable, Identifiable {
    case ornament
    case beachPohutukawa
    case bushWalk
    case clearBlueSea
    case clifftopCoast
    case coastalSunrise
    case estuarySunset
    case jettyHarbour
    case sandyBeach
    case sunsetRocks

    var id: String { rawValue }

    static let storageKey = "communityCalendar.wallpaperStyle"

    static func style(for rawValue: String) -> PCCWallpaperStyle {
        PCCWallpaperStyle(rawValue: rawValue) ?? .ornament
    }

    var title: String {
        switch self {
        case .ornament: return "Original"
        case .beachPohutukawa: return "Pohutukawa Beach"
        case .bushWalk: return "Bush Walk"
        case .clearBlueSea: return "Clear Blue Sea"
        case .clifftopCoast: return "Clifftop Coast"
        case .coastalSunrise: return "Coastal Sunrise"
        case .estuarySunset: return "Estuary Sunset"
        case .jettyHarbour: return "Jetty Harbour"
        case .sandyBeach: return "Sandy Beach"
        case .sunsetRocks: return "Sunset Rocks"
        }
    }

    var assetName: String? {
        switch self {
        case .ornament: return nil
        case .beachPohutukawa: return "PCCWallpaperBeachPohutukawa"
        case .bushWalk: return "PCCWallpaperBushWalk"
        case .clearBlueSea: return "PCCWallpaperClearBlueSea"
        case .clifftopCoast: return "PCCWallpaperClifftopCoast"
        case .coastalSunrise: return "PCCWallpaperCoastalSunrise"
        case .estuarySunset: return "PCCWallpaperEstuarySunset"
        case .jettyHarbour: return "PCCWallpaperJettyHarbour"
        case .sandyBeach: return "PCCWallpaperSandyBeach"
        case .sunsetRocks: return "PCCWallpaperSunsetRocks"
        }
    }
}

enum PCCCardTintStyle: String, CaseIterable, Identifiable {
    case clean
    case warm
    case sage
    case sky
    case blush

    var id: String { rawValue }

    static let storageKey = "communityCalendar.cardTintStyle"

    static func style(for rawValue: String) -> PCCCardTintStyle {
        PCCCardTintStyle(rawValue: rawValue) ?? .clean
    }

    var title: String {
        switch self {
        case .clean: return "Clean white"
        case .warm: return "Warm cream"
        case .sage: return "Soft sage"
        case .sky: return "Coastal blue"
        case .blush: return "Pohutukawa blush"
        }
    }

    var fill: Color {
        switch self {
        case .clean:
            return .white.opacity(0.94)
        case .warm:
            return PCCTheme.cream.opacity(0.94)
        case .sage:
            return Color(red: 0.88, green: 0.93, blue: 0.86).opacity(0.94)
        case .sky:
            return Color(red: 0.86, green: 0.94, blue: 0.97).opacity(0.94)
        case .blush:
            return Color(red: 1.00, green: 0.90, blue: 0.86).opacity(0.94)
        }
    }

    var previewColor: Color {
        switch self {
        case .clean: return .white
        case .warm: return PCCTheme.cream
        case .sage: return Color(red: 0.78, green: 0.88, blue: 0.75)
        case .sky: return Color(red: 0.74, green: 0.88, blue: 0.94)
        case .blush: return Color(red: 0.98, green: 0.74, blue: 0.66)
        }
    }
}

struct PCCScreenBackground: View {
    @AppStorage(PCCWallpaperStyle.storageKey) private var selectedWallpaper = PCCWallpaperStyle.ornament.rawValue

    var body: some View {
        let style = PCCWallpaperStyle.style(for: selectedWallpaper)

        ZStack {
            if let assetName = style.assetName {
                Image(assetName)
                    .resizable()
                    .scaledToFill()
                    .ignoresSafeArea()

                LinearGradient(
                    colors: [
                        .white.opacity(0.22),
                        PCCTheme.cream.opacity(0.14),
                        PCCTheme.deepGreen.opacity(0.12)
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                )
                .ignoresSafeArea()

            } else {
                PCCTheme.cream.ignoresSafeArea()

                LinearGradient(
                    colors: [
                        .white.opacity(0.95),
                        PCCTheme.cream.opacity(0.95),
                        Color(red: 0.95, green: 0.91, blue: 0.82)
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                )
                .ignoresSafeArea()

                PCCWallpaperOrnament()
                    .opacity(0.92)
                    .ignoresSafeArea()
            }
        }
    }
}

struct PCCWallpaperOrnament: View {
    var body: some View {
        GeometryReader { geo in
            let width = max(geo.size.width, 1)
            let height = max(geo.size.height, 1)

            ZStack {
                FlowerCluster(scale: 1.05)
                    .position(x: 26, y: 64)

                FlowerCluster(scale: 0.82)
                    .rotationEffect(.degrees(12))
                    .position(x: max(width - 22, 0), y: 88)

                FlowerCluster(scale: 0.92)
                    .rotationEffect(.degrees(180))
                    .position(x: 34, y: max(height - 34, 0))

                FlowerCluster(scale: 1.15)
                    .rotationEffect(.degrees(190))
                    .position(x: max(width - 36, 0), y: max(height - 54, 0))

                CoastalMist()
                    .frame(height: 160)
                    .position(x: width / 2, y: max(height - 116, 0))
            }
        }
        .allowsHitTesting(false)
    }
}

struct CoastalMist: View {
    var body: some View {
        ZStack {
            Capsule()
                .fill(Color.blue.opacity(0.05))
                .blur(radius: 18)
                .offset(y: 36)

            Path { path in
                path.move(to: CGPoint(x: 0, y: 120))
                path.addCurve(
                    to: CGPoint(x: 420, y: 96),
                    control1: CGPoint(x: 120, y: 64),
                    control2: CGPoint(x: 260, y: 132)
                )
                path.addLine(to: CGPoint(x: 420, y: 180))
                path.addLine(to: CGPoint(x: 0, y: 180))
                path.closeSubpath()
            }
            .fill(PCCTheme.leafGreen.opacity(0.07))
            .blur(radius: 2)
        }
    }
}

struct FlowerCluster: View {
    let scale: CGFloat

    var body: some View {
        ZStack {
            ForEach(0..<9, id: \.self) { index in
                LeafShape()
                    .fill(PCCTheme.leafGreen.opacity(0.78))
                    .frame(width: 16 * scale, height: 44 * scale)
                    .rotationEffect(.degrees(Double(index) * 26 - 95))
                    .offset(x: CGFloat(index % 3 - 1) * 18 * scale, y: CGFloat(index) * 2 * scale)
            }

            ForEach(0..<3, id: \.self) { index in
                PohutukawaBloom()
                    .frame(width: 72 * scale, height: 72 * scale)
                    .offset(x: CGFloat(index - 1) * 34 * scale, y: CGFloat(index % 2) * 18 * scale)
            }
        }
    }
}

struct PohutukawaBloom: View {
    var body: some View {
        ZStack {
            ForEach(0..<28, id: \.self) { index in
                Capsule()
                    .fill(PCCTheme.pohutukawaRed.opacity(0.82))
                    .frame(width: 2.2, height: 34)
                    .offset(y: -16)
                    .rotationEffect(.degrees(Double(index) * 360.0 / 28.0))
            }

            Circle()
                .fill(PCCTheme.pohutukawaOrange)
                .frame(width: 10, height: 10)
        }
    }
}

struct LeafShape: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.midX, y: rect.minY))
        path.addCurve(
            to: CGPoint(x: rect.midX, y: rect.maxY),
            control1: CGPoint(x: rect.maxX, y: rect.height * 0.25),
            control2: CGPoint(x: rect.maxX, y: rect.height * 0.78)
        )
        path.addCurve(
            to: CGPoint(x: rect.midX, y: rect.minY),
            control1: CGPoint(x: rect.minX, y: rect.height * 0.78),
            control2: CGPoint(x: rect.minX, y: rect.height * 0.25)
        )
        return path
    }
}

extension View {
    func pccCardStyle() -> some View {
        modifier(PCCCardSurfaceModifier())
    }

    func pccScreenTitleStyle() -> some View {
        font(.title2.weight(.black))
            .foregroundStyle(PCCTheme.screenSectionTitle)
    }

    func pccScreenSubtitleStyle() -> some View {
        font(.subheadline.weight(.bold))
            .foregroundStyle(PCCTheme.screenSubtitle)
    }

    func pccScreenBodyStyle() -> some View {
        font(.body.weight(.medium))
            .foregroundStyle(PCCTheme.screenSubtitle)
            .lineSpacing(3)
    }

    func pccSettingsSectionTitleStyle() -> some View {
        font(.subheadline.weight(.black))
            .foregroundStyle(PCCTheme.screenSectionTitle)
            .textCase(.uppercase)
    }

    func pccSettingsFooterStyle() -> some View {
        font(.footnote.weight(.medium))
            .foregroundStyle(PCCTheme.screenSectionFooter)
    }

    func pccCardTitleStyle() -> some View {
        font(.headline.weight(.black))
            .foregroundStyle(PCCTheme.cardTitle)
    }

    func pccCardBodyStyle() -> some View {
        font(.body.weight(.medium))
            .foregroundStyle(PCCTheme.cardBody)
            .lineSpacing(3)
    }

    func pccCardMetaStyle() -> some View {
        font(.caption.weight(.bold))
            .foregroundStyle(PCCTheme.cardMeta)
    }
}

private struct PCCCardSurfaceModifier: ViewModifier {
    @AppStorage(PCCCardTintStyle.storageKey) private var selectedCardTint = PCCCardTintStyle.clean.rawValue

    func body(content: Content) -> some View {
        let style = PCCCardTintStyle.style(for: selectedCardTint)

        content
            .background(style.fill, in: RoundedRectangle(cornerRadius: PCCTheme.cardRadius, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: PCCTheme.cardRadius, style: .continuous)
                    .stroke(.white.opacity(0.92), lineWidth: 1)
            )
            .shadow(color: PCCTheme.deepGreen.opacity(0.08), radius: 18, x: 0, y: 10)
    }
}
