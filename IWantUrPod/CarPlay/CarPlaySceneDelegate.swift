// CarPlay scene delegate. Architecture source: docs/design/carplay-ia.md (v1) +
// IWantUrPod/App/Info.plist (CPTemplateApplicationSceneSessionRoleApplication →
// $(PRODUCT_MODULE_NAME).CarPlaySceneDelegate). This is the M1 dormant seam: it
// owns the CPInterfaceController and installs the root template via the factory,
// but carries no playback logic — data/transport are injected through
// CarPlayIntegration so PlaybackKit can light this up at M3.
#if canImport(CarPlay)
import CarPlay
import UIKit
import PodcastModels

/// The CarPlay scene delegate referenced by Info.plist. On connect it builds the
/// root `CPTabBarTemplate` via `CarPlayTemplateFactory` and installs it on the
/// supplied `CPInterfaceController`, holding both for the scene's lifetime.
@MainActor
final class CarPlaySceneDelegate: UIResponder, CPTemplateApplicationSceneDelegate {

    /// The live interface controller for this CarPlay scene.
    private var interfaceController: CPInterfaceController?

    /// The factory that assembles and pushes templates for this scene.
    private var factory: CarPlayTemplateFactory?

    func templateApplicationScene(
        _ templateApplicationScene: CPTemplateApplicationScene,
        didConnect interfaceController: CPInterfaceController
    ) {
        self.interfaceController = interfaceController

        // Use the M3-registered provider if present; otherwise stay inert with
        // empty content so the template tree still renders (empty-state rows).
        let provider = CarPlayIntegration.contentProvider ?? EmptyCarPlayContentProvider()
        let factory = CarPlayTemplateFactory(content: provider)
        factory.interfaceController = interfaceController
        self.factory = factory

        interfaceController.setRootTemplate(
            factory.makeRootTemplate(),
            animated: true,
            completion: nil
        )
    }

    func templateApplicationScene(
        _ templateApplicationScene: CPTemplateApplicationScene,
        didDisconnectInterfaceController interfaceController: CPInterfaceController
    ) {
        self.interfaceController = nil
        self.factory = nil
    }
}
#endif
