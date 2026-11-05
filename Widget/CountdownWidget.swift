import AppIntents
import SwiftUI
import WidgetKit

@main
struct CountdownWidgetBundle: WidgetBundle {
    var body: some Widget {
        CountdownWidget()
    }
}

// MARK: - Configuración del widget (editable manteniendo pulsado el widget)

struct ConfigIntent: WidgetConfigurationIntent {
    static var title: LocalizedStringResource = "Cuenta atrás"
    static var description = IntentDescription("Elige la fecha y hora objetivo.")

    @Parameter(title: "Nombre")
    var name: String?

    @Parameter(title: "Contar desde", default: .auto)
    var unit: CountdownUnit

    // Opción 1: escribir la fecha completa. Si está rellena, tiene prioridad.
    @Parameter(title: "Fecha en texto", description: "Formato: 2027-12-06 18:30")
    var dateText: String?

    // Opción 2: campos numéricos (funcionan en cualquier versión de iOS).
    @Parameter(title: "Año", default: 2027)
    var year: Int

    @Parameter(title: "Mes (1-12)", default: 1)
    var month: Int

    @Parameter(title: "Día", default: 1)
    var day: Int

    @Parameter(title: "Hora (0-23)", default: 0)
    var hour: Int

    @Parameter(title: "Minuto (0-59)", default: 0)
    var minute: Int

    @Parameter(title: "Usar datos de la app", default: false)
    var useApp: Bool

    /// Fecha objetivo: el texto si es válido; si no, los campos numéricos.
    var targetDate: Date {
        if let parsed = Self.parse(dateText) { return parsed }
        let comps = DateComponents(year: year, month: month, day: day, hour: hour, minute: minute)
        return Calendar.current.date(from: comps) ?? Date(timeIntervalSinceNow: 30 * 86_400)
    }

    /// Interpreta "2027-12-06 18:30", "2027-12-06T18:30" o "2027-12-06".
    static func parse(_ text: String?) -> Date? {
        guard let text = text?.trimmingCharacters(in: .whitespacesAndNewlines), !text.isEmpty else { return nil }
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = .current
        for format in ["yyyy-MM-dd HH:mm:ss", "yyyy-MM-dd HH:mm", "yyyy-MM-dd'T'HH:mm", "yyyy-MM-dd"] {
            f.dateFormat = format
            if let date = f.date(from: text) { return date }
        }
        return nil
    }
}

// MARK: - Entrada del timeline

struct Column: Hashable {
    let value: Int
    let letter: String
}

struct CountdownEntry: TimelineEntry {
    enum State { case empty, running, finished }

    let date: Date
    let state: State
    let title: String
    /// Números estáticos (años, meses, días...) con su letra.
    let columns: [Column]
    /// Cronómetro vivo (h:mm:ss o mm:ss). Lo dibuja el sistema, así que cuenta solo cada segundo.
    let timer: ClosedRange<Date>?
    let timerShowsHours: Bool

    static let placeholder = CountdownEntry(
        date: .now, state: .running, title: "Evento",
        columns: [Column(value: 1, letter: "A"), Column(value: 1, letter: "M"), Column(value: 13, letter: "D")],
        timer: Date.now...Date.now.addingTimeInterval(11 * 3600 + 15 * 60 + 30),
        timerShowsHours: true
    )

    static func empty(_ date: Date = .now) -> CountdownEntry {
        CountdownEntry(date: date, state: .empty, title: "", columns: [], timer: nil, timerShowsHours: false)
    }
}

// MARK: - Provider

struct Provider: AppIntentTimelineProvider {
    func placeholder(in context: Context) -> CountdownEntry { .placeholder }

    func snapshot(for configuration: ConfigIntent, in context: Context) async -> CountdownEntry {
        makeEntries(configuration).entries.first ?? .placeholder
    }

    func timeline(for configuration: ConfigIntent, in context: Context) async -> Timeline<CountdownEntry> {
        let result = makeEntries(configuration)
        return Timeline(entries: result.entries, policy: result.finished ? .never : .atEnd)
    }

    private func makeEntries(_ config: ConfigIntent) -> (entries: [CountdownEntry], finished: Bool) {
        let target: Date
        let unit: CountdownUnit
        let title: String
        if config.useApp {
            guard let appDate = SharedStore.targetDate else { return ([.empty()], true) }
            target = appDate
            unit = SharedStore.unit
            title = SharedStore.title
        } else {
            target = config.targetDate
            unit = config.unit
            title = config.name ?? ""
        }
        let cal = CountdownMath.calendar

        var entries: [CountdownEntry] = []
        var d = Date()
        let perSecond = unit == .minutes || unit == .seconds   // aquí no hay cronómetro posible

        func add(_ columns: [Column], timer: ClosedRange<Date>? = nil, hours: Bool = false) {
            entries.append(CountdownEntry(date: d, state: .running, title: title, columns: columns,
                                          timer: timer, timerShowsHours: hours))
        }

        while d < target && entries.count < 150 {
            let sig = CountdownMath.significant(unit: unit, from: d, to: target)
            let columns = sig.map { Column(value: $0.value, letter: CountdownMath.letter($0.component)) }

            if perSecond {
                add(columns)
                d = d.addingTimeInterval(1)
                continue
            }

            switch sig[0].component {
            case .year, .month, .day:
                // Años/meses/días estáticos + cronómetro h:mm:ss con lo que sobra del día.
                let ymd = sig.filter { [.year, .month, .day].contains($0.component) }
                var dc = DateComponents()
                for item in ymd { dc.setValue(item.value, for: item.component) }
                let base = cal.date(byAdding: dc, to: d) ?? d
                let end = d.addingTimeInterval(max(0, target.timeIntervalSince(base)))
                add(ymd.map { Column(value: $0.value, letter: CountdownMath.letter($0.component)) },
                    timer: d...end, hours: true)
                d = end.addingTimeInterval(1)   // al cambiar el día entra la siguiente entrada
            case .hour:
                add([], timer: d...target, hours: true)
                d = target.addingTimeInterval(-3599)   // cuando queda < 1 h se ocultan las horas
            case .minute:
                add([], timer: d...target, hours: false)
                d = target.addingTimeInterval(-59)     // en el último minuto: solo segundos
            default:
                add(columns)
                d = d.addingTimeInterval(1)
            }
        }

        let finished = d >= target
        if finished {
            entries.append(CountdownEntry(date: max(target, Date()), state: .finished, title: title,
                                          columns: [], timer: nil, timerShowsHours: false))
        }
        return (entries, finished)
    }
}

// MARK: - Vistas

struct TimerBlock: View {
    let range: ClosedRange<Date>
    let showsHours: Bool
    let size: CGFloat

    private var hoursDigits: Int {
        max(1, String(Int(range.upperBound.timeIntervalSince(range.lowerBound) / 3600)).count)
    }
    private var sample: String {
        showsHours ? String(repeating: "0", count: hoursDigits) + ":00:00" : "00:00"
    }
    private var cw: CGFloat { size * 0.6 }   // ancho de un carácter monoespaciado

    private func tag(_ text: String, width: CGFloat) -> some View {
        Text(text)
            .font(.system(size: size * 0.38, weight: .medium))
            .foregroundStyle(.secondary)
            .frame(width: width)
    }

    var body: some View {
        VStack(alignment: .trailing, spacing: 0) {
            ZStack(alignment: .trailing) {
                Text(sample).hidden()   // fija el ancho; el cronómetro, si no, ocupa todo el espacio
                Text(timerInterval: range, countsDown: true, showsHours: showsHours)
                    .multilineTextAlignment(.trailing)
            }
            .font(.system(size: size, weight: .semibold, design: .monospaced))
            .monospacedDigit()

            HStack(spacing: 0) {
                if showsHours {
                    tag("H", width: cw * CGFloat(hoursDigits))
                    Spacer().frame(width: cw)
                }
                tag("M", width: cw * 2)
                Spacer().frame(width: cw)
                tag("S", width: cw * 2)
            }
        }
        .fixedSize()
    }
}

struct CountdownWidgetView: View {
    @Environment(\.widgetFamily) private var family
    let entry: CountdownEntry

    private var size: CGFloat {
        switch family {
        case .systemSmall: 19
        case .systemMedium: 30
        default: 14
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            switch entry.state {
            case .empty:
                Text("Sin datos de la app")
                    .font(.headline)
                Text("Edita el widget y desactiva «Usar datos de la app».")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            case .finished:
                if !entry.title.isEmpty { Text(entry.title).font(.caption).foregroundStyle(.secondary) }
                Text("¡Llegó el momento!").font(.headline)
            case .running:
                if !entry.title.isEmpty {
                    Text(entry.title)
                        .font(family == .accessoryRectangular ? .caption2 : .caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                HStack(alignment: .top, spacing: size * 0.5) {
                    ForEach(entry.columns, id: \.self) { column in
                        VStack(spacing: 0) {
                            Text("\(column.value)")
                                .font(.system(size: size, weight: .semibold, design: .monospaced))
                            Text(column.letter)
                                .font(.system(size: size * 0.38, weight: .medium))
                                .foregroundStyle(.secondary)
                        }
                    }
                    if let timer = entry.timer {
                        TimerBlock(range: timer, showsHours: entry.timerShowsHours, size: size)
                    }
                }
                .lineLimit(1)
                .minimumScaleFactor(0.5)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        .containerBackground(.fill.tertiary, for: .widget)
    }
}

// MARK: - Widget

struct CountdownWidget: Widget {
    var body: some WidgetConfiguration {
        AppIntentConfiguration(kind: "CountdownWidget", intent: ConfigIntent.self, provider: Provider()) { entry in
            CountdownWidgetView(entry: entry)
        }
        .configurationDisplayName("Cuenta atrás")
        .description("Tiempo restante hasta tu fecha.")
        .supportedFamilies([.systemSmall, .systemMedium, .accessoryRectangular])
    }
}
