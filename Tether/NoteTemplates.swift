import Foundation

/// A reusable note body template.
struct NoteTemplate: Codable, Identifiable, Hashable {
    var id: UUID
    var name: String
    var body: String
}

/// Built-in templates plus user templates stored in UserDefaults.
///
/// Future work: in-app UI for creating/editing custom templates. The storage
/// layer (`saveCustomTemplates`) is already in place for that milestone.
enum TemplateStore {
    private static let customKey = "TetherCustomTemplates"

    static let blank = NoteTemplate(
        id: UUID(uuidString: "00000000-0000-0000-0000-000000000001")!,
        name: "Blank",
        body: ""
    )

    static let aiGeneration = NoteTemplate(
        id: UUID(uuidString: "00000000-0000-0000-0000-000000000002")!,
        name: "AI Generation",
        body: """
        Prompt:

        Model:

        Voice:

        Links:

        """
    )

    static let builtIn: [NoteTemplate] = [blank, aiGeneration]

    static func all() -> [NoteTemplate] {
        builtIn + custom()
    }

    static func custom() -> [NoteTemplate] {
        guard let data = UserDefaults.standard.data(forKey: customKey) else { return [] }
        return (try? JSONDecoder().decode([NoteTemplate].self, from: data)) ?? []
    }

    static func saveCustomTemplates(_ templates: [NoteTemplate]) {
        if let data = try? JSONEncoder().encode(templates) {
            UserDefaults.standard.set(data, forKey: customKey)
        }
    }
}
