import SwiftUI

struct SilenceConfigPanel: View {
    @Bindable var vm: ProjectViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("靜音偵測設定")
                .font(.headline)

            VStack(alignment: .leading, spacing: 4) {
                Text("音量閾值：\(String(format: "%.0f", vm.silenceConfig.thresholdDB)) dB")
                    .font(.caption)
                Slider(
                    value: $vm.silenceConfig.thresholdDB,
                    in: -60...(-10),
                    step: 1
                )
                Text("低於此音量的區段將被視為靜音並移除")
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
            }

            VStack(alignment: .leading, spacing: 4) {
                Text("最短靜音時長：\(String(format: "%.1f", vm.silenceConfig.minDuration)) 秒")
                    .font(.caption)
                Slider(
                    value: $vm.silenceConfig.minDuration,
                    in: 0.1...3.0,
                    step: 0.1
                )
                Text("短於此時長的靜音不會被移除")
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
            }

            VStack(alignment: .leading, spacing: 4) {
                Text("邊緣預留間距：\(String(format: "%.1f", vm.silenceConfig.paddingDuration)) 秒")
                    .font(.caption)
                Slider(
                    value: $vm.silenceConfig.paddingDuration,
                    in: 0...1.0,
                    step: 0.05
                )
                Text("在有聲音的前後各保留此緩衝時間，避免剪輯過於緊湊")
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
            }

            Divider()

            Text("調整後可在下方音頻軌道（A）即時預覽閾值線")
                .font(.system(size: 10))
                .foregroundStyle(.secondary)
        }
        .padding()
        .frame(width: 280)
    }
}
