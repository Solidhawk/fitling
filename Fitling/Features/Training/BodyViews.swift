import Charts
import PhotosUI
import SwiftUI
import FitlingCore

/// Body weight and circumferences: a chart, the list and a row to add one (TASKS 4.8).
struct BodyView: View {
    let log: BodyLog
    @State private var kind: MeasurementKind = .weight
    @State private var measurements: [BodyMeasurement] = []
    @State private var value: Double?
    @State private var date = Date.now

    init(log: BodyLog) {
        self.log = log
    }

    private var symbol: String {
        kind.isWeight ? log.weightSymbol : log.lengthSymbol
    }

    var body: some View {
        List {
            Section {
                Picker("body.kind", selection: $kind) {
                    ForEach(MeasurementKind.allCases) { kind in
                        Text(kind.titleKey).tag(kind)
                    }
                }
                .tint(Color.ink)
                if measurements.count >= 2 {
                    Chart(measurements) { measurement in
                        LineMark(
                            x: .value("training.chart.date", Day(isoString: measurement.measuredOn)?.startDate ?? .now),
                            y: .value("body.value", log.displayValue(measurement))
                        )
                        .foregroundStyle(Color.ink)
                    }
                    .chartYScale(domain: .automatic(includesZero: false))
                    .chartYAxisLabel(symbol)
                    .frame(height: 180)
                }
            }
            .listRowBackground(Color.card)

            Section {
                HStack {
                    TextField("body.value", value: $value, format: .number)
                        .keyboardType(.decimalPad)
                        .font(.title3.weight(.semibold))
                        .accessibilityIdentifier("body.value")
                    Text(verbatim: symbol).foregroundStyle(Color.inkSoft)
                }
                DatePicker("body.date", selection: $date, in: ...Date.now, displayedComponents: .date)
                    .tint(Color.ink)
                Button("body.add") {
                    if let value, log.add(value, kind: kind, on: Day(date, timeZone: .current)) != nil {
                        self.value = nil
                        reload()
                    }
                }
                .disabled(value.flatMap { log.storedValue($0, kind: kind) } == nil)
                .accessibilityIdentifier("body.add")
            } header: {
                Text("body.new")
            }
            .listRowBackground(Color.card)

            if !measurements.isEmpty {
                Section("body.history") {
                    ForEach(measurements.reversed()) { measurement in
                        HStack {
                            Text(Day(isoString: measurement.measuredOn)?.startDate ?? .now, format: .dateTime.day().month().year())
                            Spacer()
                            Text(verbatim: "\(log.displayValue(measurement).formatted(.number.precision(.fractionLength(0...1)))) \(symbol)")
                                .fontWeight(.heavy)
                                .monospacedDigit()
                        }
                        .accessibilityElement(children: .combine)
                    }
                    .onDelete { offsets in
                        let shown = Array(measurements.reversed())
                        for index in offsets { log.delete(shown[index]) }
                        reload()
                    }
                }
                .listRowBackground(Color.card)
            }
        }
        .foregroundStyle(Color.ink)
        .groundBackground()
        .navigationTitle("body.title")
        .onAppear(perform: reload)
        .onChange(of: kind) { _, _ in reload() }
    }

    private func reload() {
        measurements = log.measurements(of: kind)
    }
}

/// Progress photos in a grid, newest first. Only on this device (TASKS 4.9).
struct ProgressPhotosView: View {
    let store: ProgressPhotoStore
    @State private var photos: [ProgressPhoto] = []
    @State private var picked: PhotosPickerItem?
    @State private var opened: ProgressPhoto?
    @State private var failed = false

    init(store: ProgressPhotoStore) {
        self.store = store
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Spacing.l) {
                Text("photos.privacy").font(.footnote).foregroundStyle(Color.inkSoft)
                PhotosPicker(selection: $picked, matching: .images) {
                    Label("photos.add", systemImage: "plus")
                }
                .buttonStyle(SecondaryButtonStyle())
                if photos.isEmpty {
                    Text("photos.empty").footerStyle()
                }
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 104), spacing: Spacing.s)], spacing: Spacing.s) {
                    ForEach(photos) { photo in
                        Button {
                            opened = photo
                        } label: {
                            PhotoTile(url: store.url(of: photo), day: Day(isoString: photo.takenOn))
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            .padding(Spacing.l)
        }
        .foregroundStyle(Color.ink)
        .background(Color.ground)
        .navigationTitle("photos.title")
        .onAppear(perform: reload)
        .onChange(of: picked) { _, item in
            guard let item else { return }
            Task {
                if let data = try? await item.loadTransferable(type: Data.self), let jpeg = UIImage(data: data)?.jpegData(compressionQuality: 0.85) {
                    do { try store.add(jpeg) } catch { failed = true }
                } else {
                    failed = true
                }
                picked = nil
                reload()
            }
        }
        .sheet(item: $opened, onDismiss: reload) { photo in
            PhotoDetail(url: store.url(of: photo), day: Day(isoString: photo.takenOn)) {
                store.delete(photo)
            }
        }
        .alert("photos.failed", isPresented: $failed) {
            Button("common.ok", role: .cancel) {}
        }
    }

    private func reload() {
        photos = store.photos()
    }
}

/// The date on a progress photo: a small chip at the bottom of the tile.
enum PhotoDateChip {
    static let foreground = ColorResource.ink
    static let background = ColorResource.track
}

private struct PhotoTile: View {
    let url: URL
    let day: Day?

    var body: some View {
        Color.track
            .aspectRatio(3 / 4, contentMode: .fit)
            .overlay {
                if let image = UIImage(contentsOfFile: url.path()) {
                    Image(uiImage: image).resizable().scaledToFill()
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            .overlay(alignment: .bottomLeading) {
                if let day {
                    Text(day.startDate, format: .dateTime.day().month(.abbreviated))
                        .font(.caption.weight(.bold))
                        .foregroundStyle(Color(PhotoDateChip.foreground))
                        .padding(.horizontal, Spacing.s)
                        .padding(.vertical, Spacing.xs)
                        .background(Color(PhotoDateChip.background), in: Capsule())
                        .padding(Spacing.s)
                }
            }
            .accessibilityElement(children: .combine)
            .accessibilityLabel(day.map { Text($0.startDate, format: .dateTime.day().month().year()) } ?? Text("photos.title"))
    }
}

private struct PhotoDetail: View {
    let url: URL
    let day: Day?
    let onDelete: () -> Void
    @State private var confirming = false
    @Environment(\.dismiss) private var dismiss

    init(url: URL, day: Day?, onDelete: @escaping () -> Void) {
        self.url = url
        self.day = day
        self.onDelete = onDelete
    }

    var body: some View {
        NavigationStack {
            Group {
                if let image = UIImage(contentsOfFile: url.path()) {
                    Image(uiImage: image).resizable().scaledToFit()
                } else {
                    Color.track
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Color.ground)
            .navigationTitle(day.map { Text($0.startDate, format: .dateTime.day().month().year()) } ?? Text("photos.title"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("common.ok") { dismiss() }
                }
                ToolbarItem(placement: .destructiveAction) {
                    Button("photos.delete", role: .destructive) { confirming = true }
                }
            }
            .confirmationDialog("photos.delete.title", isPresented: $confirming, titleVisibility: .visible) {
                Button("photos.delete", role: .destructive) {
                    onDelete()
                    dismiss()
                }
            }
        }
    }
}

extension MeasurementKind {
    var titleKey: LocalizedStringKey {
        switch self {
        case .weight: "body.weight"
        case .waist: "body.waist"
        case .chest: "body.chest"
        case .hips: "body.hips"
        case .arm: "body.arm"
        case .thigh: "body.thigh"
        case .neck: "body.neck"
        }
    }
}
