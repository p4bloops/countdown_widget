import SwiftUI
import WidgetKit

@main
struct CountdownWidgetBundle: WidgetBundle {
    var body: some Widget {
        CountdownWidget()
    }
}

// MARK: - Entrada del timeline

struct CountdownEntry: TimelineEntry {
    enum State { case empty, running, finished }

    let date: Date
    let state: State
    let title: String
    let unit: CountdownUnit
    /// Texto de las unidades "estáticas" (ej. ["1 año", "1 mes", "1 día"]).
    let staticParts: [String]
    /// Rango del cronómetro vivo (horas:min:seg restantes de la unidad actual).
    let timer: ClosedRange<Date>?

    static let placeholder = CountdownEntry(
        date: .now, state: .running, title: "Evento", unit: .years,
        staticParts: ["1 año", "1 mes", "1 día"],
        timer: Date.now...Date.now.addingTimeInterval(3600 * 5)
    )

    static func empty(_ date: Date = .now) -> CountdownEntry {
        CountdownEntry(date: date, state: .empty, title: "", unit: .days, staticParts: [], timer: nil)
    }
}

// MARK: - Provider

struct Provider: TimelineProvider {
    func placeholder(in context: Context) -> CountdownEntry { .placeholder }

    func getSnapshot(in context: Context, completion: @escaping (CountdownEntry) -> Void) {
        completion(makeEntries().first ?? .placeholder)
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<CountdownEntry>) -> Void) {
        let entries = makeEntries()
        let finished = entries.last?.state != .running
        completion(Timeline(entries: entries, policy: finished ? .never : .atEnd))
    }

    private func makeEntries() -> [CountdownEntry] {
        guard let target = SharedStore.targetDate else { return [.empty()] }
        let unit = SharedStore.unit
        let title = SharedStore.title
        let calendar = CountdownMath.calendar

        var entries: [CountdownEntry] = []
        var d = Date()
        let maxEntries = unit == .seconds ? 120 : 48

        while d < target && entries.count < maxEntries {
            let c = calendar.dateComponents(Set(unit.staticComponents), from: d, to: target)
            let parts = unit.staticComponents.map { CountdownMath.label($0, CountdownMath.value(c, $0)) }

            // Tiempo que sobra una vez restadas las unidades estáticas: lo cuenta el cronómetro vivo.
            let base = calendar.date(byAdding: c, to: d) ?? d
            let remainder = max(0, target.timeIntervalSince(base))
            let end = d.addingTimeInterval(remainder)

            entries.append(CountdownEntry(
                date: d, state: .running, title: title, unit: unit, staticParts: parts,
                timer: unit.liveTimerShowsHours == nil ? nil : d...end
            ))

            // Siguiente entrada: justo cuando las unidades estáticas cambian.
            d = unit == .seconds ? d.addingTimeInterval(1) : end.addingTimeInterval(1)
        }

        if d >= target {
            entries.append(CountdownEntry(date: target, state: .finished, title: title, unit: unit,
                                          staticParts: [], timer: nil))
        }
        return entries
    }
}

// MARK: - Vista

struct CountdownWidgetView: View {
    @Environment(\.widgetFamily) private var family
    let entry: CountdownEntry

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            switch entry.state {
            case .empty:
                Text("Abre la app y elige una fecha")
                    .font(.headline)
            case .finished:
                if !entry.title.isEmpty { Text(entry.title).font(.caption).foregroundStyle(.secondary) }
                Text("¡Llegó el momento!").font(.title2.bold())
            case .running:
                if !entry.title.isEmpty {
                    Text(entry.title).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                }
                ForEach(entry.staticParts, id: \.self) { part in
                    Text(part)
                        .font(.system(size: family == .systemSmall ? 22 : 26, weight: .bold, design: .rounded))
                        .minimumScaleFactor(0.5)
                        .lineLimit(1)
                }
                if let timer = entry.timer, let showsHours = entry.unit.liveTimerShowsHours {
                    Text(timerInterval: timer, countsDown: true, showsHours: showsHours)
                        .font(.system(size: family == .systemSmall ? 20 : 24, weight: .semibold, design: .monospaced))
                        .monospacedDigit()
                        .multilineTextAlignment(.leading)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .foregroundStyle(.tint)
                    Text(entry.unit.liveTimerCaption)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        .containerBackground(.fill.tertiary, for: .widget)
    }
}

// MARK: - Widget

struct CountdownWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "CountdownWidget", provider: Provider()) { entry in
            CountdownWidgetView(entry: entry)
        }
        .configurationDisplayName("Cuenta atrás")
        .description("Tiempo restante hasta tu fecha.")
        .supportedFamilies([.systemSmall, .systemMedium])
    }
}
