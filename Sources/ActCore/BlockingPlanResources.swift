import Foundation

/// The TypeScript editor is bundled locally; it does not load remote content.
public enum BlockingPlanResources {
    public static var editorURL: URL? { Bundle.module.url(forResource: "BlockingPlans", withExtension: "html") }
}
