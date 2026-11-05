import SwiftUI
import WidgetKit

struct ContentView: View {
    @State private var target: Date = SharedStore.targetDate
        ?? Calendar.current.date(byAdding: .month, value: 1, to: .now)!
    @State private var unit: CountdownUnit = SharedStore.unit   // .auto por defecto
    @State private var title: String = SharedStore.title

    var body: some View {
        TabView {
            dateTab.tabItem { Label("Fecha", systemImage: "calendar") }
            formatTab.tabItem { Label("Formato", systemImage: "textformat.123") }
        }
        .onAppear(perform: save)
        .onChange(of: target) { save() }
        .onChange(of: unit) { save() }
        .onChange(of: title) { save() }
    }

    private var dateTab: some View {
        NavigationStack {
            Form {
                Section("Nombre (opcional)") {
                    TextField("Ej. Viaje a Japón", text: $title)
                }
                Section("Fecha y hora objetivo") {
                    DatePicker(
                        "Fecha y hora",
                        selection: $target,
                        in: Date.now...,
                        displayedComponents: [.date, .hourAndMinute]
                    )
                    .datePickerStyle(.graphical)
                }
            }
            .navigationTitle("Cuenta atrás")
        }
    }

    private var formatTab: some View {
        NavigationStack {
            Form {
                Section("Contar desde") {
                    Picker("Unidad", selection: $unit) {
                        ForEach(CountdownUnit.allCases) { Text($0.title).tag($0) }
                    }
                    .pickerStyle(.inline)
                    .labelsHidden()
                }
                Section("Vista previa") {
                    TimelineView(.periodic(from: .now, by: 1)) { context in
                        Text(CountdownMath.parts(unit: unit, from: context.date, to: target)
                            .joined(separator: ", "))
                            .font(.title3.monospacedDigit())
                    }
                }
                Section {
                    Text("«Automático» oculta las unidades que valen 0 a la izquierda. Añade el widget desde la pantalla de inicio o de bloqueo. Mantén pulsado el widget → Editar widget para elegir su fecha. «Usar datos de la app» solo funciona si iOS deja compartirlos (con Apple ID gratis suele no dejar).")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
            .navigationTitle("Formato")
        }
    }

    private func save() {
        SharedStore.targetDate = target
        SharedStore.unit = unit
        SharedStore.title = title
        WidgetCenter.shared.reloadAllTimelines()
    }
}
