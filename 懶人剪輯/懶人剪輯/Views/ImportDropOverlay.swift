import SwiftUI
import UniformTypeIdentifiers

struct ImportDropOverlay: View {
    @Bindable var vm: ProjectViewModel
    @State private var isTargeted = false

    var body: some View {
        Rectangle()
            .fill(.clear)
            .overlay {
                if isTargeted {
                    RoundedRectangle(cornerRadius: 12)
                        .strokeBorder(Color.accentColor, style: StrokeStyle(lineWidth: 3, dash: [10]))
                        .background(Color.accentColor.opacity(0.12).clipShape(RoundedRectangle(cornerRadius: 12)))
                        .overlay {
                            VStack(spacing: 8) {
                                Image(systemName: "arrow.down.doc.fill")
                                    .font(.system(size: 40))
                                Text("拖放影片到此處")
                                    .font(.title3.weight(.medium))
                            }
                            .foregroundStyle(.white.opacity(0.8))
                        }
                        .padding(20)
                }
            }
            .dropDestination(for: URL.self) { urls, _ in
                let videoURLs = urls.filter { url in
                    Constants.supportedVideoTypes.contains(url.pathExtension.lowercased())
                }
                guard !videoURLs.isEmpty else { return false }
                vm.importFiles(urls: videoURLs)
                return true
            } isTargeted: { targeted in
                isTargeted = targeted
            }
    }
}
