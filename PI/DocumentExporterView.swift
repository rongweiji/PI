//
//  DocumentExporterView.swift
//  PI
//
//  Created by Rongwei Ji on 11/5/25.
//

import SwiftUI
import UniformTypeIdentifiers

struct DocumentExporterView: UIViewControllerRepresentable {
    var url: URL
    var onComplete: () -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(onComplete: onComplete)
    }

    func makeUIViewController(context: Context) -> UIDocumentPickerViewController {
        let controller = UIDocumentPickerViewController(forExporting: [url], asCopy: true)
        controller.delegate = context.coordinator
        controller.allowsMultipleSelection = false
        return controller
    }

    func updateUIViewController(_ uiViewController: UIDocumentPickerViewController, context: Context) {}

    final class Coordinator: NSObject, UIDocumentPickerDelegate {
        private let onComplete: () -> Void

        init(onComplete: @escaping () -> Void) {
            self.onComplete = onComplete
        }

        func documentPickerWasCancelled(_ controller: UIDocumentPickerViewController) {
            onComplete()
        }

        func documentPicker(_ controller: UIDocumentPickerViewController, didPickDocumentsAt urls: [URL]) {
            onComplete()
        }
    }
}
