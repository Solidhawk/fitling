import SwiftUI
import UIKit

/// The camera for one still photo, such as the nutrition table of a package. Only offered where there is a camera.
struct CameraPicker: UIViewControllerRepresentable {
    let onPhoto: @MainActor (UIImage) -> Void
    @Environment(\.dismiss) private var dismiss

    static var isAvailable: Bool {
        UIImagePickerController.isSourceTypeAvailable(.camera)
    }

    func makeUIViewController(context: Context) -> UIImagePickerController {
        let picker = UIImagePickerController()
        picker.sourceType = .camera
        picker.delegate = context.coordinator
        return picker
    }

    func updateUIViewController(_ controller: UIImagePickerController, context: Context) {}

    func makeCoordinator() -> Coordinator {
        Coordinator(onPhoto: onPhoto, dismiss: dismiss)
    }

    @MainActor
    final class Coordinator: NSObject, @preconcurrency UIImagePickerControllerDelegate, @preconcurrency UINavigationControllerDelegate {
        let onPhoto: @MainActor (UIImage) -> Void
        let dismiss: DismissAction

        init(onPhoto: @escaping @MainActor (UIImage) -> Void, dismiss: DismissAction) {
            self.onPhoto = onPhoto
            self.dismiss = dismiss
        }

        func imagePickerController(_ picker: UIImagePickerController, didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]) {
            // Encoded away from the main actor by whoever reads it: a large photo would make the camera stutter.
            if let image = info[.originalImage] as? UIImage { onPhoto(image) }
            dismiss()
        }

        func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
            dismiss()
        }
    }
}
