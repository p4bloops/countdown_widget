import Foundation

// MARK: - Unidad de inicio

enum CountdownUnit: String, CaseIterable, Identifiable {
    case years, months, days, hours, minutes, seconds

    var id: String { rawValue }

    var title: String {
        switch self {
        case .years: "Años"
        case .months: "Meses"
        case .days: "Días"
        case .hours: "Horas"
        case .minutes: "Minutos"
        case .seconds: "Segundos"
        }
    }

    /// Todas las unidades que se muestran, desde la elegida hasta segundos.
    var components: [Calendar.Component] {
        let all: [Calendar.Component] = [.year, .month, .day, .hour, .minute, .second]
        let start: Calendar.Component = switch self {
        case .years: .year
        case .months: .month
        case .days: .day
        case .hours: .hour
        case .minutes: .minute
        case .seconds: .second
        }
        return Array(all[all.firstIndex(of: start)!...])
    }

    /// Unidades "estáticas" del widget: las que cambian poco. El resto se muestra con un cronómetro vivo.
    var staticComponents: [Calendar.Component] {
        switch self {
        case .years: [.year, .month, .day]
        case .months: [.month, .day]
        case .days: [.day]
        case .hours: [.hour]
        case .minutes: [.minute]
        case .seconds: [.second]
        }
    }

    /// El cronómetro vivo muestra h:mm:ss (true), m:ss (false) o no se muestra (nil).
    var liveTimerShowsHours: Bool? {
        switch self {
        case .years, .months, .days: true
        case .hours, .minutes: false
        case .seconds: nil
        }
    }

    var liveTimerCaption: String {
        switch self {
        case .years, .months, .days: "horas : min : seg"
        case .hours, .minutes: "min : seg"
        case .seconds: ""
        }
    }
}

// MARK: - Cálculo

enum CountdownMath {
    static var calendar: Calendar { Calendar.current }

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

    /// Ej.: ["1 año", "1 mes", "1 día", "0 horas", "0 minutos", "12 segundos"]
    static func parts(unit: CountdownUnit, from: Date, to: Date) -> [String] {
        let comps = calendar.dateComponents(Set(unit.components), from: from, to: max(from, to))
        return unit.components.map { label($0, value(comps, $0)) }
    }
}

// MARK: - Almacenamiento compartido app <-> widget

enum SharedStore {
    static let defaultGroup = "group.com.pablogv.countdown"

    /// AltStore reescribe el App Group al instalar y lo deja en Info.plist (ALTAppGroups).
    static var groupID: String {
        (Bundle.main.object(forInfoDictionaryKey: "ALTAppGroups") as? [String])?.first ?? defaultGroup
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
        get { CountdownUnit(rawValue: defaults.string(forKey: "unit") ?? "") ?? .days }
        set { defaults.set(newValue.rawValue, forKey: "unit") }
    }

    static var title: String {
        get { defaults.string(forKey: "title") ?? "" }
        set { defaults.set(newValue, forKey: "title") }
    }
}
