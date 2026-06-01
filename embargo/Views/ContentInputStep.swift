import SwiftUI
import PhotosUI

struct ContentInputStep: View {
    let selectedType: CapsuleType?
    @Binding var textContent: String
    @Binding var selectedPhoto: PhotosPickerItem?
    @Binding var imageData: Data?
    @Binding var audioFileName: String?
    @Bindable var audioManager: AudioManager
    @State private var appeared = false

    private var contentTitle: String {
        switch selectedType {
        case .text: "write it down"
        case .photo: "preserve that moment"
        case .voice: "say it out loud"
        case nil: "add your content"
        }
    }

    var body: some View {
        VStack(spacing: selectedType == .photo && imageData != nil ? 8 : 24) {
            Spacer()

            Text(contentTitle)
                .font(.title2.weight(.light))
                .tracking(Design.trackingNormal)

            Group {
                switch selectedType {
                case .text:
                    TextContentEditor(textContent: $textContent)
                case .photo:
                    PhotoContentEditor(selectedPhoto: $selectedPhoto, imageData: $imageData)
                case .voice:
                    AudioRecorderView(audioManager: audioManager, recordedFileName: $audioFileName)
                case nil:
                    EmptyView()
                }
            }
            .padding(.horizontal, 24)
            .opacity(appeared ? 1 : 0)
            .offset(y: appeared ? 0 : 16)

            Spacer()
        }
        .onAppear {
            withAnimation(.easeOut(duration: 0.4).delay(0.1)) { appeared = true }
        }
    }
}
