#if canImport(SwiftUI)
import SwiftUI
import IlumCore

struct GeodesyReferenceView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var query = ""

    private var results: [GeodesyReferenceEntry] {
        query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            ? GeodesyReferenceCatalog.entries
            : GeodesyReferenceCatalog.search(query, limit: GeodesyReferenceCatalog.entries.count)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Geodäsie · Німеччина / NRW").font(.title2.bold())
                    Text("\(GeodesyReferenceCatalog.entries.count) тем · Переглянуто \(GeodesyReferenceCatalog.snapshotDate)")
                        .font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                Button("Закрити") { dismiss() }.keyboardShortcut(.cancelAction)
            }
            Text("Офлайн-довідник: федеральні теми та NRW. Короткі пояснення, не повні тексти законів. Дата перегляду не означає чинність редакції. Для роботи перевіряйте зміни, місцевий Bebauungsplan і дату проєкту за офіційним джерелом.")
                .font(.callout).foregroundStyle(.secondary)
            TextField("GRZ, Erhebungserlass, Lageplan, межі, координати…", text: $query)
                .textFieldStyle(.roundedBorder)
                .accessibilityLabel("Пошук у довіднику геодезиста")
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 12) {
                    if results.isEmpty {
                        Text("Теми не знайдено. Спробуйте німецький термін або українське ключове слово. Довідник поки охоплює не всі теми та землі Німеччини.")
                            .foregroundStyle(.secondary).padding()
                    }
                    ForEach(results) { entry in
                        referenceCard(entry)
                    }
                }
            }
            Text("Пошук працює без моделі та інтернету. Посилання відкривають джерела у браузері. У чаті можна запитати українською або німецькою.")
                .font(.caption).foregroundStyle(.secondary)
        }
        .padding(20)
        .frame(minWidth: 620, idealWidth: 740, minHeight: 480, idealHeight: 680)
    }

    private func referenceCard(_ entry: GeodesyReferenceEntry) -> some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 8) {
                Text(entry.title).font(.headline)
                Text("\(entry.jurisdiction) · \(entry.kind) · \(entry.section)")
                    .font(.caption).foregroundStyle(.secondary)
                Text(entry.summary)
                Text(entry.caution).font(.callout).foregroundStyle(.secondary)
                Divider()
                Text("Редакція: \(entry.sourceEdition)").font(.caption)
                Text("\(entry.publisher) · Переглянуто: \(entry.reviewedOn)")
                    .font(.caption).foregroundStyle(.secondary)
                if let url = URL(string: entry.sourceURL) {
                    Link(entry.sourceURL, destination: url).font(.caption)
                }
                ForEach(entry.relatedSourceURLs, id: \.self) { source in
                    if let url = URL(string: source) {
                        Link(source, destination: url).font(.caption)
                    }
                }
            }
            .textSelection(.enabled)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(4)
        }
    }
}
#endif
