// Bundled-font registration. Design source: docs/design/direction.md §3.
// Registers the brand display face so `Font.custom` can find it inside an SPM
// resource bundle (fonts are not auto-registered for library targets).
//
// AVAILABLE: IBMPlexMono-Regular.ttf (weight 400) — copied from
//   design/kit/fonts/. PostScript name "IBMPlexMono-Regular", family "IBM Plex Mono".
// MISSING (fall back to system): all other IBM Plex Mono weights (Thin…Bold,
//   incl. the 800/heavy used by large-title/section/nav-title) and the entire
//   Roboto UI family. Display roles at heavy weights render Regular until the
//   extra faces are added to Fonts/; UI/body roles use the system font.
import CoreText
import Foundation

public enum FontRegistration {
    /// The registered display family/PostScript name usable with `Font.custom`.
    /// IBM Plex Mono registers under its family name "IBM Plex Mono".
    public static let displayFontName = "IBM Plex Mono"

    /// The single bundled face's file (sans extension).
    private static let bundledFaces = ["IBMPlexMono-Regular"]

    private static var didRegister = false

    /// Register all bundled fonts with Core Text. Idempotent; call once at
    /// app launch (e.g. in the App initializer) before rendering custom fonts.
    public static func registerFonts() {
        guard !didRegister else { return }
        didRegister = true

        for face in bundledFaces {
            guard let url = Bundle.module.url(forResource: face, withExtension: "ttf") else {
                assertionFailure("DesignSystem: bundled font \(face).ttf not found in module bundle")
                continue
            }
            var error: Unmanaged<CFError>?
            if !CTFontManagerRegisterFontsForURL(url as CFURL, .process, &error) {
                // Already-registered is benign; anything else we surface in debug.
                if let err = error?.takeUnretainedValue() {
                    let code = CFErrorGetCode(err)
                    // kCTFontManagerErrorAlreadyRegistered == 105
                    if code != 105 {
                        assertionFailure("DesignSystem: failed to register \(face): \(err)")
                    }
                }
            }
        }
    }
}
