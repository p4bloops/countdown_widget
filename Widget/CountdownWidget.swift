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
    static var description = IntentDescription("Por defecto usa la fecha elegida en la app.")

    @Parameter(title: "Usar datos de la app", default: true)
    var useApp: Bool

    // Lo de abajo solo se usa si «Usar datos de la app» está apagado (o la app no comparte datos).
    @Parameter(title: "Nombre")
    var name: String?

    @Parameter(title: "Contar desde", default: .auto)
    var unit: CountdownUnit

    // Opción 1: escribir la fecha completa. Si está rellena, tiene prioridad sobre los campos numéricos.
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

    var fieldsDate: Date {
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
    /// Cronómetro vivo. Lo dibuja el sistema, así que cuenta solo cada segundo.
    let timer: ClosedRange<Date>?
    /// true: horas+minutos+segundos. false: minutos+segundos.
    let timerShowsHours: Bool
    /// Fecha objetivo en texto (diagnóstico).
    var targetLabel: String = ""
    /// Explicación cuando no hay fecha.
    var note: String = ""

    static let placeholder = CountdownEntry(
        date: .now, state: .running, title: "Evento",
        columns: [Column(value: 1, letter: "A"), Column(value: 1, letter: "M"), Column(value: 13, letter: "D")],
        timer: Date.now...Date.now.addingTimeInterval(11 * 3600 + 15 * 60 + 30),
        timerShowsHours: true
    )

    static func empty(_ note: String) -> CountdownEntry {
        CountdownEntry(date: .now, state: .empty, title: "", columns: [], timer: nil,
                       timerShowsHours: false, note: note)
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

    /// Prioridad: datos de la app > fecha en texto > campos numéricos (solo si no se usa la app).
    private func resolve(_ config: ConfigIntent) -> (target: Date, unit: CountdownUnit, title: String)? {
        if config.useApp, let appDate = SharedStore.targetDate {
            let title = SharedStore.title.isEmpty ? (config.name ?? "") : SharedStore.title
            return (appDate, SharedStore.unit, title)
        }
        if let parsed = ConfigIntent.parse(config.dateText) {
            return (parsed, config.unit, config.name ?? "")
        }
        if !config.useApp {
            return (config.fieldsDate, config.unit, config.name ?? "")
        }
        return nil
    }

    private func makeEntries(_ config: ConfigIntent) -> (entries: [CountdownEntry], finished: Bool) {
        guard let (target, unit, title) = resolve(config) else {
            let note = SharedStore.isGroupAvailable
                ? "Elige la fecha en la app."
                : "iOS no comparte datos con la app. Edita el widget, apaga «Usar datos de la app» y escribe la fecha."
            return ([.empty(note)], true)
        }
        let cal = CountdownMath.calendar
        let labelFormatter = DateFormatter()
        labelFormatter.dateFormat = "yyyy-MM-dd HH:mm"
        let label = labelFormatter.string(from: target)

        var entries: [CountdownEntry] = []
        var d = Date()
        let perSecond = unit == .minutes || unit == .seconds   // aquí no hay cronómetro posible

        func add(_ date: Date, _ columns: [Column], timer: ClosedRange<Date>? = nil, hours: Bool = false) {
            entries.append(CountdownEntry(date: date, state: .running, title: title, columns: columns,
                                          timer: timer, timerShowsHours: hours, targetLabel: label))
        }

        /// Una entrada con cronómetro, más otra cuando el primer campo pasa a un solo dígito (para mostrar "09").
        func addTimer(_ columns: [Column], from start: Date, to end: Date, hours: Bool) {
            add(start, columns, timer: start...end, hours: hours)
            let threshold: TimeInterval = hours ? 36_000 : 600
            if end.timeIntervalSince(start) > threshold {
                let later = end.addingTimeInterval(-threshold + 1)
                add(later, columns, timer: later...end, hours: hours)
            }
        }

        while d < target && entries.count < 150 {
            let sig = CountdownMath.significant(unit: unit, from: d, to: target)
            let columns = sig.map { Column(value: $0.value, letter: CountdownMath.letter($0.component)) }

            if perSecond {
                add(d, columns)
                d = d.addingTimeInterval(1)
                continue
            }

            switch sig[0].component {
            case .year, .month, .day:
                // Años/meses/días estáticos + cronómetro h m s con lo que sobra del día.
                let ymd = sig.filter { [.year, .month, .day].contains($0.component) }
                var dc = DateComponents()
                for item in ymd { dc.setValue(item.value, for: item.component) }
                let base = cal.date(byAdding: dc, to: d) ?? d
                let end = d.addingTimeInterval(max(0, target.timeIntervalSince(base)))
                addTimer(ymd.map { Column(value: $0.value, letter: CountdownMath.letter($0.component)) },
                         from: d, to: end, hours: true)
                d = end.addingTimeInterval(1)   // al cambiar el día entra la siguiente entrada
            case .hour:
                addTimer([], from: d, to: target, hours: true)
                d = target.addingTimeInterval(-3599)   // cuando queda < 1 h se ocultan las horas
            case .minute:
                addTimer([], from: d, to: target, hours: false)
                d = target.addingTimeInterval(-59)     // en el último minuto: solo segundos
            default:
                add(d, columns)
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

/// Un campo (horas, minutos o segundos) recortado del cronómetro del sistema.
/// El sistema dibuja "9:44:05"; mostramos solo una ventana del texto para quitar los ":".
struct TimerField: View {
    let range: ClosedRange<Date>
    let showsHours: Bool
    let size: CGFloat
    /// Caracteres (contados desde la derecha) que hay que saltarse para llegar a este campo.
    let shift: Int
    /// Dígitos que muestra la ventana.
    let cells: Int
    /// Antepone un "0" fijo (cuando el primer campo tiene un solo dígito).
    let pad: Bool

    var body: some View {
        let cw = size * 0.6   // ancho de un carácter monoespaciado
        let font = Font.system(size: size, weight: .semibold, design: .monospaced)
        HStack(spacing: 0) {
            if pad { Text("0").font(font) }
            Text(timerInterval: range, countsDown: true, showsHours: showsHours)
                .font(font)
                .multilineTextAlignment(.trailing)
                .lineLimit(1)
                .frame(width: cw * 16, alignment: .trailing)
                .offset(x: CGFloat(shift) * cw)
                .frame(width: cw * CGFloat(cells), alignment: .trailing)
                .clipped()
        }
        .frame(height: size * 1.25)
    }
}

struct CountdownWidgetView: View {
    @Environment(\.widgetFamily) private var family
    @Environment(\.isLuminanceReduced) private var dimmed   // Always-On Display
    let entry: CountdownEntry

    private var groupCount: Int {
        entry.columns.count + (entry.timer == nil ? 0 : (entry.timerShowsHours ? 3 : 2))
    }

    /// Tamaño de letra que hace caber todos los grupos en el ancho disponible.
    private var size: CGFloat {
        let (available, maxSize): (CGFloat, CGFloat) = switch family {
        case .systemSmall: (122, 26)
        case .systemMedium: (295, 36)
        default: (140, 18)
        }
        let n = CGFloat(max(1, groupCount))
        let units = n * 1.2 + (n - 1) * 0.55
        return min(maxSize, available / units)
    }

    private func letterFont(_ size: CGFloat) -> Font { .system(size: max(8, size * 0.4), weight: .medium) }

    private func group<Number: View>(_ number: Number, _ letter: String, hidden: Bool = false) -> some View {
        VStack(spacing: 0) {
            number
            Text(letter).font(letterFont(size)).foregroundStyle(.secondary)
        }
        .opacity(hidden ? 0 : 1)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            switch entry.state {
            case .empty:
                Text("Sin fecha").font(.headline)
                Text(entry.note)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            case .finished:
                if !entry.title.isEmpty { Text(entry.title).font(.caption).foregroundStyle(.secondary) }
                Text("¡Llegó el momento!").font(.headline)
            case .running:
                if !entry.title.isEmpty {
                    Text(entry.title)
                        .font(family == .accessoryRectangular ? .caption : .subheadline)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                counter
                if family != .accessoryRectangular, !entry.targetLabel.isEmpty {
                    Text("→ \(entry.targetLabel)")
                        .font(.system(size: 10))
                        .foregroundStyle(.secondary)
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        .containerBackground(.fill.tertiary, for: .widget)
    }

    private var counter: some View {
        let size = self.size
        let cw = size * 0.6
        return HStack(alignment: .top, spacing: size * 0.55) {
            ForEach(entry.columns, id: \.self) { column in
                group(
                    Text(String(format: "%02d", column.value))
                        .font(.system(size: size, weight: .semibold, design: .monospaced))
                        .frame(height: size * 1.25),
                    column.letter,
                    hidden: dimmed && column.letter == "S"
                )
            }
            if let timer = entry.timer {
                timerGroups(timer, size: size, cw: cw)
            }
        }
        .lineLimit(1)
    }

    @ViewBuilder
    private func timerGroups(_ range: ClosedRange<Date>, size: CGFloat, cw: CGFloat) -> some View {
        let remaining = range.upperBound.timeIntervalSince(range.lowerBound)
        let first = Int(remaining / (entry.timerShowsHours ? 3600 : 60))
        let firstDigits = max(1, String(first).count)
        let pad = firstDigits == 1

        if entry.timerShowsHours {
            group(TimerField(range: range, showsHours: true, size: size, shift: 6, cells: firstDigits, pad: pad), "H")
            group(TimerField(range: range, showsHours: true, size: size, shift: 3, cells: 2, pad: false), "M")
        } else {
            group(TimerField(range: range, showsHours: false, size: size, shift: 3, cells: firstDigits, pad: pad), "M")
        }
        // Con la pantalla en reposo (Always-On) los segundos no se pueden actualizar: se ocultan.
        group(
            TimerField(range: range, showsHours: entry.timerShowsHours, size: size, shift: 0, cells: 2, pad: false),
            "S",
            hidden: dimmed
        )
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
