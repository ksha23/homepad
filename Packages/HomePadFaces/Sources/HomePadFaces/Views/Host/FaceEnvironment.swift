import Foundation
import HomePadCore
import SwiftUI

extension EnvironmentValues {
    /// The saved configuration the face should draw. Set by `HostedFace`.
    @Entry var faceConfiguration: FaceConfiguration = .unsaved("")

    /// Shifts the clock for screenshots of other times of day (debug launch argument).
    @Entry var faceTimeOffset: TimeInterval = 0

    /// True inside a face (`HostedFace`), so a face nested in it (Smart
    /// Rotation's) draws one face, not the wall's pages.
    @Entry var isInsideFaceHost: Bool = false

    /// True when personal content may show: the member was recognized, or a
    /// debug launch argument forces it for screenshots.
    @Entry var facesShowPersonal: Bool = false

    /// True in face previews (the editor, My Faces, the gallery). Personal
    /// widgets then keep their place while nobody is recognized, drawn locked,
    /// so the layout matches what a recognized member sees. The live face
    /// leaves them out instead, with their cells left empty, so nothing
    /// moves when someone is recognized.
    @Entry var facesKeepsPersonalPlaces: Bool = false

    /// True where the face is drawn without its widgets, because something
    /// else draws them: the face editor's widgets page, where they can be moved.
    @Entry var facesHidesWidgetLayer: Bool = false

    /// The room a face keeps its own content out of, from its edges: the Now
    /// Playing pill's at the top while it shows (`\.faceNowPlayingRoom`), and
    /// the face's widget area, up to a gap before it, while the face has
    /// widgets there (`FaceWidgetSupport.widgetRoom`). `\.faceInsets`
    /// includes it. A face that centers its content on the whole face rather
    /// than inside its insets (Night, Critters, the dials) centers it in the
    /// rest (`CGSize.leaving(_:)`).
    @Entry var faceKeepClear = EdgeInsets()

    /// The face's top trailing corner, where the shell draws the profile
    /// button (`FaceWidgetSupport.profileZone`), in the face's coordinates.
    /// Null outside a hosted face. A face whose content reaches that corner
    /// moves it clear (`EdgeInsets.clearing(_:in:)`).
    @Entry var faceProfileZone = CGRect.null

    /// True while the face has widgets of its own (`HostedFace`). A face whose
    /// content stays put and blocks its cells (`FaceContentRegion`), and
    /// that spreads over the whole face without widgets, keeps inside its
    /// region while it has them: Analog's numerals.
    @Entry var faceHasWidgets = false

    /// True for a face on the wall beside the one at rest, built ahead of a
    /// swipe, while none of it shows (`FacePager`). It holds still then: no
    /// motion (`faceAllowsMotion`), and its clock ticks once a minute.
    @Entry var faceIsBeside = false

    /// True where face cards are covered, as My Faces is under the editor and
    /// the gallery. Their pictures are not taken again until they show
    /// (`FaceStill`).
    @Entry var facesPausesStills = false

    /// Core's `allowsContinuousMotion`, and false for a face beside the one
    /// at rest. Faces with motion of their own read this one.
    var faceAllowsMotion: Bool {
        allowsContinuousMotion && !faceIsBeside
    }
}

/// Debug launch arguments for screenshots, read once. Release builds ignore them.
///
///     -HomePadFacesNight YES          render in the red night palette
///     -HomePadFacesPersonal YES       show personal calendar content
///     -HomePadFacesTime 21:30         pretend it is this time of day
///     -HomePadFacesStyle digital      show the face in this style choice
///     -HomePadFacesColors midnight,cream,orange
///                                     show the face in this background, text and accent
///                                     (an empty part keeps the saved one, auto picks automatic)
///     -HomePadFacesWeather rain       pretend the weather is rain, snow, clear, cloudy, thunder or fog
///     -HomePadFacesLandscape YES      lay the face out in landscape, turned to fit a portrait
///                                     simulator (rotate the screenshot to view it)
///     -HomePadFacesWidgets "personal.weather:medium@4,0;kitchen.timers:small"
///                                     put these widgets on the face (`FaceDebugWidgets`)
///     -HomePadFacesMiniWidget "shell.glance.mini:small"
///                                     put this mini widget in the face's top left corner
enum FaceDebugOptions {
    static var forcesNight: Bool { flag("HomePadFacesNight") }
    static var forcesPersonal: Bool { flag("HomePadFacesPersonal") }
    static var forcesLandscape: Bool { flag("HomePadFacesLandscape") }

    /// A style choice to show instead of the saved one.
    static var styleOverride: String? {
        #if DEBUG
        UserDefaults.standard.string(forKey: "HomePadFacesStyle")
        #else
        nil
        #endif
    }

    /// The configuration with `-HomePadFacesStyle` applied.
    static func withStyleOverride(_ configuration: FaceConfiguration) -> FaceConfiguration {
        guard let style = styleOverride else { return configuration }
        var configuration = configuration
        configuration.values["style"] = style
        return configuration
    }

    /// The configuration with `-HomePadFacesColors` applied.
    static func withColorOverride(_ configuration: FaceConfiguration) -> FaceConfiguration {
        #if DEBUG
        guard let colors = UserDefaults.standard.string(forKey: "HomePadFacesColors") else { return configuration }
        var configuration = configuration
        let keys = ["color", FaceColorChoice.textKey, FaceColorChoice.accentKey]
        for (key, part) in zip(keys, colors.split(separator: ",", omittingEmptySubsequences: false)) where !part.isEmpty {
            configuration.values[key] = part == "auto" ? nil : String(part)
        }
        return configuration
        #else
        return configuration
        #endif
    }

    /// The overrides the face on the wall takes: colors and widgets.
    static func withWallOverrides(_ configuration: FaceConfiguration) -> FaceConfiguration {
        withWidgetOverride(withColorOverride(configuration))
    }

    static var weatherOverride: String? {
        #if DEBUG
        UserDefaults.standard.string(forKey: "HomePadFacesWeather")
        #else
        nil
        #endif
    }

    /// Seconds to add to the real clock so it reads the requested time today.
    static func timeOffset(now: Date = Date(), calendar: Calendar = .current) -> TimeInterval {
        #if DEBUG
        guard let text = UserDefaults.standard.string(forKey: "HomePadFacesTime") else { return 0 }
        let parts = text.split(separator: ":").compactMap { Int($0) }
        guard parts.count == 2,
              let target = calendar.date(bySettingHour: parts[0], minute: parts[1], second: 0, of: now) else { return 0 }
        return target.timeIntervalSince(now)
        #else
        return 0
        #endif
    }

    private static func flag(_ key: String) -> Bool {
        #if DEBUG
        UserDefaults.standard.bool(forKey: key)
        #else
        false
        #endif
    }
}
