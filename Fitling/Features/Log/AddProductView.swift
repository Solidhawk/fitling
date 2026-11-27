import AVFoundation
import PhotosUI
import SwiftUI
import FitlingCore

struct AddProductView: View {
    @State private var viewModel: AddProductViewModel
    @State private var photographing = false
    @State private var picked: PhotosPickerItem?
    @Environment(\.openURL) private var openURL
    private let onSaved: (Product) -> Void

    init(viewModel: AddProductViewModel, onSaved: @escaping (Product) -> Void) {
        _viewModel = State(initialValue: viewModel)
        self.onSaved = onSaved
    }

    var body: some View {
        Form {
            labelSection

            Section {
                TextField("product.add.name", text: $viewModel.name)
                    .accessibilityIdentifier("product.add.name")
                TextField("product.add.brand", text: $viewModel.brand)
                TextField("product.add.barcode", text: $viewModel.gtin)
                    .keyboardType(.numberPad)
            }
            .listRowBackground(Color.card)

            Section {
                Picker("portion.unit", selection: $viewModel.isMillilitre) {
                    Text("portion.unit.gram").tag(false)
                    Text("portion.unit.millilitre").tag(true)
                }
                .pickerStyle(.segmented)
                numberField("product.add.kcal", value: $viewModel.kcal, identifier: "product.add.kcal")
                numberField("product.add.protein", value: $viewModel.protein, identifier: "product.add.protein")
                numberField("product.add.carbs", value: $viewModel.carbs, identifier: "product.add.carbs")
                numberField("product.add.fat", value: $viewModel.fat, identifier: "product.add.fat")
            } header: {
                Text("product.add.per100").foregroundStyle(Color.ink).textCase(nil)
            }
            .listRowBackground(Color.card)

            Section {
                numberField("product.add.serving", value: $viewModel.servingSize, identifier: "product.add.serving")
            } footer: {
                Text("product.add.serving.footer").footerStyle()
            }
            .listRowBackground(Color.card)

            Section {
                SubmitButton(title: "product.add.save", isWorking: false) {
                    if let product = viewModel.save() { onSaved(product) }
                }
                .disabled(!viewModel.canSave)
                .accessibilityIdentifier("product.add.save")
                .buttonRow()
            } footer: {
                Text("product.add.rules").footerStyle()
            }
        }
        .foregroundStyle(Color.ink)
        .groundBackground()
        .navigationTitle("product.add.title")
        .navigationBarTitleDisplayMode(.inline)
        .fullScreenCover(isPresented: $photographing) {
            CameraPicker { image in
                Task { await read { image.jpegData(compressionQuality: 0.9) } }
            }
            .ignoresSafeArea()
        }
        .onChange(of: picked) { _, item in
            guard let item else { return }
            picked = nil
            Task { await read { try? await item.loadTransferable(type: Data.self) } }
        }
    }

    /// Reads the photo, then says what came of it to VoiceOver as well: the note under the buttons changes quietly.
    private func read(_ load: @escaping @Sendable () async -> Data?) async {
        await viewModel.readLabel(load)
        AccessibilityNotification.Announcement(String(localized: labelNote)).post()
    }

    /// A photo of the nutrition table fills the values; the user checks them (TASKS 2.8).
    private var labelSection: some View {
        Section {
            if CameraPicker.isAvailable {
                if cameraRefused {
                    // Refused earlier, for the barcode: the camera would only show black.
                    Button {
                        if let url = URL(string: UIApplication.openSettingsURLString) { openURL(url) }
                    } label: {
                        Label("product.label.camera.settings", systemImage: "camera")
                    }
                } else {
                    Button {
                        photographing = true
                    } label: {
                        Label("product.label.photo", systemImage: "camera")
                    }
                    .accessibilityIdentifier("product.label.photo")
                }
            }
            PhotosPicker(selection: $picked, matching: .images) {
                Label("product.label.pick", systemImage: "photo")
            }
            .accessibilityIdentifier("product.label.pick")
            if viewModel.isReadingLabel {
                ProgressView("product.label.reading")
            }
        } footer: {
            Text(labelNote).footerStyle()
        }
        .disabled(viewModel.isReadingLabel)
        .listRowBackground(Color.card)
    }

    private var labelNote: LocalizedStringResource {
        switch viewModel.labelNote {
        case nil: viewModel.isMillilitre ? "product.label.footer.ml" : "product.label.footer"
        case .read: "product.label.read"
        case .check: "product.label.check"
        case .nothing: "product.label.none"
        case .unreadable: "product.label.unreadable"
        }
    }

    private var cameraRefused: Bool {
        let status = AVCaptureDevice.authorizationStatus(for: .video)
        return status == .denied || status == .restricted
    }

    private func numberField(_ key: LocalizedStringKey, value: Binding<Double?>, identifier: String) -> some View {
        TextField(key, value: value, format: .number)
            .keyboardType(.decimalPad)
            .monospacedDigit()
            .accessibilityIdentifier(identifier)
    }
}
