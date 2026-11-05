import SwiftUI
import WidgetKit

@main
struct CountdownWidgetBundle: WidgetBundle {
    var body: some Widget {
        CountdownWidget()
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

struct Provider: TimelineProvider {
    func placeholder(in context: Context) -> CountdownEntry { .placeholder }

    func getSnapshot(in context: Context, completion: @escaping (CountdownEntry) -> Void) {
        completion(makeEntries().entries.first ?? .placeholder)
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<CountdownEntry>) -> Void) {
        let result = makeEntries()
        completion(Timeline(entries: result.entries, policy: result.finished ? .never : .atEnd))
    }

    private func makeEntries() -> (entries: [CountdownEntry], finished: Bool) {
        guard let target = SharedStore.targetDate else {
            let note = SharedStore.isGroupAvailable
                ? "Elige la fecha en la app."
                : "iOS no comparte datos con la app. Reinstala con AltStore."
            return ([.empty(note)], true)
        }
        let unit = SharedStore.unit
        let title = SharedStore.title
        let cal = CountdownMath.calendar

        var entries: [CountdownEntry] = []
        var d = Date()
        let perSecond = unit == .minutes || unit == .seconds   // aquí no hay cronómetro posible

        func add(_ date: Date, _ columns: [Column], timer: ClosedRange<Date>? = nil, hours: Bool = false) {
            entries.append(CountdownEntry(date: date, state: .running, title: title, columns: columns,
                                          timer: timer, timerShowsHours: hours))
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
/// Los anchos se miden con textos ocultos, así funciona con cualquier fuente.
struct TimerField: View {
    let range: ClosedRange<Date>
    let showsHours: Bool
    let size: CGFloat
    /// Dígitos que muestra la ventana.
    let digits: Int
    /// Lo que el cronómetro dibuja a la derecha de este campo (":00:00", ":00" o "").
    let tail: String
    /// Antepone un "0" fijo (cuando el primer campo tiene un solo dígito).
    let pad: Bool

    var body: some View {
        let font = Font.system(size: size, weight: .semibold).monospacedDigit()
        let window = String(repeating: "0", count: digits)
        HStack(spacing: 0) {
            if pad { Text("0").font(font) }
            Text(window).font(font).hidden()   // define el tamaño de la ventana
                .overlay(alignment: .leading) {
                    // Mismo texto que el cronómetro, alineado para que este campo caiga dentro de la ventana.
                    Text(window + tail).font(font).fixedSize().hidden()
                        .overlay(alignment: .trailing) {
                            Text(timerInterval: range, countsDown: true, showsHours: showsHours)
                                .font(font)
                                .multilineTextAlignment(.trailing)
                                .lineLimit(1)
                                .frame(width: 400, alignment: .trailing)
                        }
                }
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

    private func group<Number: View>(_ number: Number, _ letter: String, hidden: Bool = false) -> some View {
        VStack(spacing: 0) {
            number
            Text(letter)
                .font(.system(size: max(8, size * 0.4), weight: .medium))
                .foregroundStyle(.secondary)
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
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        .containerBackground(.fill.tertiary, for: .widget)
    }

    private var counter: some View {
        let size = self.size
        return HStack(alignment: .top, spacing: size * 0.55) {
            ForEach(entry.columns, id: \.self) { column in
                group(
                    Text(String(format: "%02d", column.value))
                        .font(.system(size: size, weight: .semibold).monospacedDigit())
                        .frame(height: size * 1.25),
                    column.letter,
                    hidden: dimmed && column.letter == "S"
                )
            }
            if let timer = entry.timer {
                timerGroups(timer, size: size)
            }
        }
        .lineLimit(1)
    }

    @ViewBuilder
    private func timerGroups(_ range: ClosedRange<Date>, size: CGFloat) -> some View {
        let remaining = range.upperBound.timeIntervalSince(range.lowerBound)
        let first = Int(remaining / (entry.timerShowsHours ? 3600 : 60))
        let firstDigits = max(1, String(first).count)
        let pad = firstDigits == 1
        let hours = entry.timerShowsHours

        if hours {
            group(TimerField(range: range, showsHours: true, size: size, digits: firstDigits, tail: ":00:00", pad: pad), "H")
            group(TimerField(range: range, showsHours: true, size: size, digits: 2, tail: ":00", pad: false), "M")
        } else {
            group(TimerField(range: range, showsHours: false, size: size, digits: firstDigits, tail: ":00", pad: pad), "M")
        }
        // Con la pantalla en reposo (Always-On) los segundos no se pueden actualizar: se ocultan.
        group(
            TimerField(range: range, showsHours: hours, size: size, digits: 2, tail: "", pad: false),
            "S",
            hidden: dimmed
        )
    }
}

// MARK: - Widget

struct CountdownWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "CountdownWidget", provider: Provider()) { entry in
            CountdownWidgetView(entry: entry)
        }
        .configurationDisplayName("Cuenta atrás")
        .description("Tiempo restante hasta la fecha elegida en la app.")
        .supportedFamilies([.systemSmall, .systemMedium, .accessoryRectangular])
    }
}
