import HomePadCore
import HomePadUI
import SwiftUI
import UIKit

/// The member's wallpaper. For the Face wallpaper the shell keeps the face
/// underneath, drawing only its picture or background, and this view blurs
/// it, so the face's colors show through softly, as on HomeView's Home
/// Screen. Gradients and photos are drawn here.
struct HomeWallpaperView: View {
    let memberID: HouseholdMember.ID?
    let accent: Color

    /// In Dark, the brightest a wallpaper may be, as relative luminance: a gray of about 35 percent.
    /// A brighter one gets a black tint that brings it down to this, as iPadOS dims the wallpaper in
    /// Dark, and glass on it then turns dark. A darker one keeps its look.
    static let darkLimit = 0.1

    /// How bright a wallpaper is with its scrim and its tint in Dark, for the
    /// glass widgets on the Home Screen: a gradient from its own colors, a
    /// photo from its average color (`WallpaperPhotoStore.tone(for:)`), and
    /// the face from the tone it reports. Nil while a photo is being measured
    /// or a face reports none, and glass then follows the appearance.
    static func tone(_ choice: WallpaperChoice, accent: Color, hasPhoto: Bool, photoTone: BackdropTone?,
                     faceTone: BackdropTone?, scheme: ColorScheme) -> BackdropTone? {
        let tone = scrimmedTone(choice, accent: accent, hasPhoto: hasPhoto, photoTone: photoTone, faceTone: faceTone)
        return tone?.dimmed(by: darkTint(over: tone, scheme: scheme))
    }

    /// The wallpaper's tone under its scrim, before the tint in Dark.
    private static func scrimmedTone(_ choice: WallpaperChoice, accent: Color, hasPhoto: Bool, photoTone: BackdropTone?,
                                     faceTone: BackdropTone?) -> BackdropTone? {
        switch choice {
        case .face:
            return faceTone?.dimmed(by: FaceFrost.scrim)
        case .photo where hasPhoto:
            return photoTone?.dimmed(by: WallpaperBackground.photoScrim)
        default:
            // A photo wallpaper without a photo draws its gradient.
            return choice.tone(accent: accent).dimmed(by: WallpaperBackground.gradientScrim)
        }
    }

    /// The opacity of the black tint in Dark that brings a wallpaper of `tone` down to `darkLimit`.
    /// Zero in Light, for a wallpaper already that dark, and while its tone is not known yet.
    static func darkTint(over tone: BackdropTone?, scheme: ColorScheme) -> Double {
        guard scheme == .dark, let tone, tone.luminance > darkLimit else { return 0 }
        // The inverse of `BackdropTone.dimmed(by:)`.
        return 1 - pow(darkLimit / tone.luminance, 1 / 2.2)
    }

    @Environment(SettingsStore.self) private var settings
    @Environment(WallpaperPhotoStore.self) private var photos
    @Environment(\.frostedFaceTone) private var faceTone
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        let choice = settings[ShellSettings.wallpaper(for: memberID)]
        let photo = choice == .photo ? photos.image(for: memberID) : nil
        let tone = Self.scrimmedTone(choice, accent: accent, hasPhoto: photo != nil, photoTone: photos.tone(for: memberID),
                                     faceTone: faceTone)
        let tint = Self.darkTint(over: tone, scheme: scheme)
        Group {
            if choice == .face {
                FaceFrost()
            } else {
                WallpaperBackground(choice: choice, accent: accent, photo: photo)
            }
        }
        .overlay(Color.black.opacity(tint))
        // A photo's tone arrives once it is measured, and a face's changes with it, so the tint eases in.
        .animation(Theme.Motion.standard, value: tint)
        .ignoresSafeArea()
        .accessibilityHidden(true)
    }
}

extension EnvironmentValues {
    /// How bright the face kept behind the Home Screen is, as the face
    /// reports it (`BackdropToneKey`). The shell reads it from the face and
    /// hands it to the Home Screen, which draws on top of it.
    @Entry var frostedFaceTone: BackdropTone? = nil
}

/// The Face wallpaper's blur. HomeView blurs the face plainly, with no frost:
/// a material adds a gray haze and grain and its blur cannot be made smaller.
/// This blurs what is behind it with Core Animation's backdrop layer and a
/// gaussian blur (`BackdropBlur`), keeping the face's own colors, and a faint
/// scrim keeps white labels and glass buttons readable on bright faces. A
/// SwiftUI blur on the face itself breaks up faces that contain glass or
/// Metal, so the blur stays a backdrop.
struct FaceFrost: View {
    /// About half a material's blur: the face's shapes still read as soft color.
    static let blurRadius: CGFloat = 18
    /// The faint dimming over the blur.
    static let scrim = 0.08

    var body: some View {
        BackdropBlur(radius: Self.blurRadius)
            .overlay(Color.black.opacity(Self.scrim))
    }
}

/// A plain blur of whatever is drawn behind it, without a material's tint.
/// It uses `CABackdropLayer` with a `gaussianBlur` `CAFilter`, private classes
/// found by name, as HomePad does for AirPlay volume. If iPadOS ever drops
/// them, it falls back to the thinnest dark material.
struct BackdropBlur: View {
    var radius: CGFloat

    var body: some View {
        if BackdropBlurView.isAvailable {
            BackdropBlurRepresentable(radius: radius)
        } else {
            Rectangle()
                .fill(.ultraThinMaterial)
                .environment(\.colorScheme, .dark)
        }
    }
}

private struct BackdropBlurRepresentable: UIViewRepresentable {
    var radius: CGFloat

    func makeUIView(context: Context) -> BackdropBlurView {
        let view = BackdropBlurView()
        view.isUserInteractionEnabled = false
        return view
    }

    func updateUIView(_ view: BackdropBlurView, context: Context) {
        view.radius = radius
    }
}

final class BackdropBlurView: UIView {
    private static let backdropClass: AnyClass? = NSClassFromString("CABackdropLayer")
    private static let filterClass = NSClassFromString("CAFilter") as? NSObject.Type
    static var isAvailable: Bool { backdropClass != nil && filterClass != nil }

    override class var layerClass: AnyClass { backdropClass ?? CALayer.self }

    var radius: CGFloat = 0 {
        didSet { if radius != oldValue { applyBlur() } }
    }

    /// The size of the copy it blurs, against the screen. A quarter looks the same for a strong blur at
    /// far less work, but stays soft as the radius nears 0, so a blur that clears to sharp needs 1.
    var renderScale: CGFloat = 0.25 {
        didSet { layer.setValue(renderScale, forKey: "scale") }
    }

    /// The key path of the blur's radius, which Core Animation can animate.
    private static let radiusKeyPath = "filters.gaussianBlur.inputRadius"

    /// Springs the radius to `value` with `animation`'s timing, or sets it at once without one.
    /// At 0 the view hides, so a blur that is not showing costs nothing.
    func setRadius(_ value: CGFloat, animation: CASpringAnimation?) {
        guard value != radius else { return }
        let from = layer.presentation()?.value(forKeyPath: Self.radiusKeyPath) as? CGFloat ?? radius
        radius = value
        isHidden = false
        guard let animation else {
            isHidden = value == 0
            return
        }
        animation.keyPath = Self.radiusKeyPath
        animation.fromValue = from
        animation.toValue = value
        CATransaction.begin()
        CATransaction.setCompletionBlock { [weak self] in
            guard let self else { return }
            self.isHidden = self.radius == 0
        }
        layer.add(animation, forKey: "radius")
        CATransaction.commit()
    }

    private func applyBlur() {
        let make = NSSelectorFromString("filterWithType:")
        guard let filterClass = Self.filterClass, filterClass.responds(to: make),
              let blur = filterClass.perform(make, with: "gaussianBlur")?.takeUnretainedValue() as? NSObject else { return }
        // Named, so its radius can be animated by key path.
        blur.setValue("gaussianBlur", forKey: "name")
        blur.setValue(radius, forKey: "inputRadius")
        blur.setValue(true, forKey: "inputNormalizeEdges")
        layer.setValue([blur], forKey: "filters")
        layer.setValue(true, forKey: "enabled")
        layer.setValue(renderScale, forKey: "scale")
    }
}

/// Just the wallpaper fill, also used for swatches in the picker.
struct WallpaperBackground: View {
    let choice: WallpaperChoice
    let accent: Color
    let photo: UIImage?

    /// The dimming over a photo and over a gradient, so white labels read.
    static let photoScrim = 0.25
    static let gradientScrim = 0.15

    var body: some View {
        if let photo {
            GeometryReader { proxy in
                Image(uiImage: photo)
                    .resizable()
                    .scaledToFill()
                    .frame(width: proxy.size.width, height: proxy.size.height)
                    .clipped()
                    .overlay(Color.black.opacity(Self.photoScrim))
            }
        } else {
            // On black, since My Color's stops are see-through: a wallpaper is
            // content and looks the same in Light and Dark.
            LinearGradient(colors: choice.colors(accent: accent), startPoint: .topLeading, endPoint: .bottomTrailing)
                .background(Color.black)
                .overlay(Color.black.opacity(Self.gradientScrim))
        }
    }
}
