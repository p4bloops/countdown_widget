import AppIntents
import Foundation

// MARK: - Unidad de inicio

enum CountdownUnit: String, CaseIterable, Identifiable, AppEnum {
    case auto, years, months, days, hours, minutes, seconds

    var id: String { rawValue }

    var title: String {
        switch self {
        case .auto: "Automático"
        case .years: "Años"
        case .months: "Meses"
        case .days: "Días"
        case .hours: "Horas"
        case .minutes: "Minutos"
        case .seconds: "Segundos"
        }
    }

    static let typeDisplayRepresentation = TypeDisplayRepresentation(name: "Unidad")

    static let caseDisplayRepresentations: [CountdownUnit: DisplayRepresentation] = [
        .auto: DisplayRepresentation(title: "Automático"),
        .years: DisplayRepresentation(title: "Años"),
        .months: DisplayRepresentation(title: "Meses"),
        .days: DisplayRepresentation(title: "Días"),
        .hours: DisplayRepresentation(title: "Horas"),
        .minutes: DisplayRepresentation(title: "Minutos"),
        .seconds: DisplayRepresentation(title: "Segundos"),
    ]

    /// Unidades desde la elegida hasta segundos. "Automático" parte desde años.
    var components: [Calendar.Component] {
        let all: [Calendar.Component] = [.year, .month, .day, .hour, .minute, .second]
        let start: Calendar.Component = switch self {
        case .auto, .years: .year
        case .months: .month
        case .days: .day
        case .hours: .hour
        case .minutes: .minute
        case .seconds: .second
        }
        return Array(all[all.firstIndex(of: start)!...])
    }
}

// MARK: - Cálculo

enum CountdownMath {
    static var calendar: Calendar { Calendar.current }

    static func letter(_ component: Calendar.Component) -> String {
        switch component {
        case .year: "A"
        case .month: "M"
        case .day: "D"
        case .hour: "H"
        case .minute: "M"
        default: "S"
        }
    }

    static func label(_ component: Calendar.Component, _ n: Int) -> String {
        let one = n == 1
        switch component {
        case .year: return "\(n) \(one ? "año" : "años")"
        case .month: return "\(n) \(one ? "mes" : "meses")"
        case .day: return "\(n) \(one ? "día" : "días")"
        case .hour: return "\(n) \(one ? "hora" : "horas")"
        case .minute: return "\(n) \(one ? "minuto" : "minutos")"
        default: return "\(n) \(one ? "segundo" : "segundos")"
        }
    }

    static func value(_ c: DateComponents, _ component: Calendar.Component) -> Int {
        switch component {
        case .year: c.year ?? 0
        case .month: c.month ?? 0
        case .day: c.day ?? 0
        case .hour: c.hour ?? 0
        case .minute: c.minute ?? 0
        default: c.second ?? 0
        }
    }

    /// Unidades con su valor, sin los ceros de la izquierda (siempre queda al menos segundos).
    static func significant(unit: CountdownUnit, from: Date, to: Date) -> [(component: Calendar.Component, value: Int)] {
        let comps = calendar.dateComponents(Set(unit.components), from: from, to: max(from, to))
        let all = unit.components.map { (component: $0, value: value(comps, $0)) }
        let first = all.firstIndex { $0.value > 0 } ?? all.count - 1
        return Array(all[first...])
    }

    /// Ej.: ["13 días", "11 horas", "15 minutos", "30 segundos"]
    static func parts(unit: CountdownUnit, from: Date, to: Date) -> [String] {
        significant(unit: unit, from: from, to: to).map { label($0.component, $0.value) }
    }
}

// MARK: - Almacenamiento compartido app <-> widget

enum SharedStore {
    static let defaultGroup = "group.com.pablogv.countdown"

    /// AltStore reescribe el App Group al instalar y lo deja en Info.plist (ALTAppGroups).
    static var groupID: String {
        func altGroup(_ bundle: Bundle) -> String? {
            (bundle.object(forInfoDictionaryKey: "ALTAppGroups") as? [String])?.first
        }
        if let id = altGroup(Bundle.main) { return id }
        // Dentro del widget (.app/PlugIns/X.appex): probar con la app contenedora.
        let parent = Bundle.main.bundleURL.deletingLastPathComponent().deletingLastPathComponent()
        if parent.pathExtension == "app", let bundle = Bundle(url: parent), let id = altGroup(bundle) { return id }
        return defaultGroup
    }

    /// true si iOS concedió el App Group (sin él, app y widget no pueden compartir datos).
    static var isGroupAvailable: Bool {
        FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: groupID) != nil
    }

    private static var defaults: UserDefaults {
        UserDefaults(suiteName: groupID) ?? .standard
    }

    static var targetDate: Date? {
        get {
            let t = defaults.double(forKey: "targetDate")
            return t > 0 ? Date(timeIntervalSince1970: t) : nil
        }
        set { defaults.set(newValue?.timeIntervalSince1970 ?? 0, forKey: "targetDate") }
    }

    static var unit: CountdownUnit {
        get { CountdownUnit(rawValue: defaults.string(forKey: "unit") ?? "") ?? .auto }
        set { defaults.set(newValue.rawValue, forKey: "unit") }
    }

    static var title: String {
        get { defaults.string(forKey: "title") ?? "" }
        set { defaults.set(newValue, forKey: "title") }
    }
}
