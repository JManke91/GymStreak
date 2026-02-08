import SwiftUI
import WatchKit

struct NewRestTimerView: View {
    @EnvironmentObject var viewModel: WatchWorkoutViewModel

    let timeRemaining: TimeInterval
    let totalDuration: TimeInterval
    let formattedTime: String
    let state: WatchWorkoutViewModel.RestTimerState
    let onSkip: () -> Void
    let onMinimize: () -> Void

    @State private var lastHapticTriggerTime: Int? = nil
    @State private var pulse = false
    @State private var backgroundPulse: CGFloat = 1.0

    var body: some View {
        ZStack {
            backgroundProgressLayer
            runningContent
        }
        .background(OnyxWatch.Colors.background)
        .onAppear { pulse = true }
        .onChange(of: shouldPulse) { isPulsing in
            if isPulsing {
                withAnimation(.easeInOut(duration: 0.6).repeatForever(autoreverses: true)) {
                    backgroundPulse = 1.03
                    pulse = true
                }
            } else {
                withAnimation(.easeInOut(duration: 0.3)) {
                    backgroundPulse = 1.0
                    pulse = false
                }
            }
        }
        .onChange(of: timeRemaining) { newTime in
            guard state == .running else { return }

            let currentSecond = Int(newTime.rounded(.up))

            // Play notification haptic at 3, 2, 1 seconds
            if [3, 2, 1].contains(currentSecond) && currentSecond != lastHapticTriggerTime {
                WKInterfaceDevice.current().play(.notification)
                lastHapticTriggerTime = currentSecond
            }

            // Play strong success haptic at 0
            if newTime <= 0.05 && lastHapticTriggerTime != 0 {
                WKInterfaceDevice.current().play(.success)
                lastHapticTriggerTime = 0
            }

            // Reset haptic tracking when above 3 seconds
            if currentSecond > 3 && lastHapticTriggerTime != nil {
                lastHapticTriggerTime = nil
            }
        }
        .animation(.spring(duration: 0.5, bounce: 0.35), value: state)
    }

    private var progressColor: Color {
            let normalizedProgress = 1.0 - progress
            let hue: Double = 0.55 - (normalizedProgress * 0.25)
            return Color(hue: hue, saturation: 0.8, brightness: 0.8)
        }

    // MARK: ─── Gradient + Glow Background
    private var backgroundProgressLayer: some View {
        Group {
            LinearGradient(
                gradient: Gradient(colors: [progressColor.opacity(0.8), .black]),
                startPoint: .bottom,
                endPoint: .top
            )
            .scaleEffect(x: 1, y: progress, anchor: .bottom)
            .animation(.linear(duration: 0.5), value: progress)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(OnyxWatch.Colors.background)
        .scaleEffect(backgroundPulse)
        .animation(.easeInOut(duration: 0.6), value: backgroundPulse)
        .ignoresSafeArea()
    }

    // MARK: ─── Running UI
    private var runningContent: some View {
        VStack(spacing: 10) {
            Text("Rest")
                .font(.headline)
                .foregroundStyle(.secondary)


            HStack(spacing: 8) {
                if let heartRate = viewModel.heartRate, let calories = viewModel.activeCalories {
                    WorkoutMetricsView(heartRate: heartRate, calories: calories, size: .medium)
                }

                Text(formattedTime)
                    .font(.system(.title, design: .rounded, weight: .bold).monospacedDigit())
                    .foregroundStyle(shouldPulse ? .red : .white)
                    .shadow(color: (shouldPulse ? Color.red : Color.white).opacity(0.5), radius: shouldPulse ? 8 : 4)
                    .scaleEffect(shouldPulse ? (pulse ? 1.15 : 1.0) : 1.0)
                    .animation(.easeInOut(duration: 0.3), value: shouldPulse)
            }


            HStack(spacing: 10) {
                Button(action: onMinimize) {
                    Image(systemName: "rectangle.compress.vertical")
                        .font(.system(size: 24, weight: .semibold))
                        .padding(2)
                }
                .tint(.gray)

                Button(action: onSkip) {
                    Text("Skip")
                        .font(.footnote.weight(.semibold))
                }
                .tint(OnyxWatch.Colors.warning)
            }
            .buttonBorderShape(.capsule)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 12)
        .opacity(state == .running ? 1 : 0)
    }

    // MARK: ─── Computed Properties

    private var progress: CGFloat {
        guard totalDuration > 0 else { return 0 }
        return CGFloat(timeRemaining / totalDuration)
    }

    /// Pulse for last 3 seconds
    private var shouldPulse: Bool {
        timeRemaining <= 3 && state == .running
    }
}



//struct RestTimerView: View {
//    let timeRemaining: TimeInterval
//    let totalDuration: TimeInterval
//    let formattedTime: String
//    let state: WatchWorkoutViewModel.RestTimerState
//    let onSkip: () -> Void
//    let onMinimize: () -> Void
//
//    var body: some View {
//        let _ = print("🎨 Rendering RestTimerView - state: \(state)")
//        ZStack {
//            // Running timer state
//            VStack(spacing: 8) {
//                Text("Rest")
//                    .font(.caption2)
//                    .foregroundStyle(.secondary)
//
//                // Large timer display
//                Text(formattedTime)
//                    .font(.system(.title, design: .rounded).monospacedDigit())
//                    .foregroundStyle(.yellow)
//                    .accessibilityLabel("Rest time remaining \(formattedTime)")
//
//                // Progress ring - slightly smaller
//                ZStack {
//                    Circle()
//                        .stroke(Color.gray.opacity(0.3), lineWidth: 5)
//
//                    Circle()
//                        .trim(from: 0, to: progress)
//                        .stroke(Color.yellow, style: StrokeStyle(lineWidth: 5, lineCap: .round))
//                        .rotationEffect(.degrees(-90))
//                        .animation(.linear(duration: 1), value: progress)
//                }
//                .frame(width: 55, height: 55)
//
//                // Horizontal button layout - only show in running state
//                HStack(spacing: 8) {
//                    Button {
//                        onMinimize()
//                    } label: {
//                        Image(systemName: "chevron.down")
//                            .font(.system(size: 14, weight: .semibold))
//                    }
////                    .buttonStyle(.bordered)
//                    .tint(.blue)
//                    .accessibilityLabel("Minimize")
//                    .accessibilityHint("Double tap to minimize rest timer")
//
//                    Button {
//                        onSkip()
//                    } label: {
//                        Text("Skip")
//                            .font(.footnote.weight(.semibold))
//                    }
////                    .buttonStyle(.bordered)
//                    .tint(OnyxWatch.Colors.warning)
//                    .accessibilityHint("Double tap to skip rest")
//                }
//                .buttonBorderShape(.capsule)
//            }
//            .opacity(state == .running ? 1 : 0)
//
//            // Beautiful completion screen
//            VStack(spacing: 12) {
//                let _ = print("✅ Completion view in hierarchy - opacity: \(state == .completed ? 1.0 : 0.0)")
//                Image(systemName: "checkmark.circle.fill")
//                    .font(.system(size: 44))
//                    .foregroundStyle(.green)
//                    .symbolEffect(.bounce, value: state == .completed)
//
//                Text("Let's Go!")
//                    .font(.system(.title2, design: .rounded, weight: .bold))
//                    .foregroundStyle(.green)
//
//                Text("Rest Complete")
//                    .font(.caption2)
//                    .foregroundStyle(.secondary)
//            }
//            .opacity(state == .completed ? 1 : 0)
//            .scaleEffect(state == .completed ? 1.0 : 0.85)
//            .accessibilityLabel("Rest complete. Let's go!")
//        }
//        .padding(.horizontal, 8)
//        .padding(.vertical, 12)
//        .frame(maxWidth: .infinity, maxHeight: .infinity)
//        .background(Color(.black))
//        .animation(.spring(response: 0.4, dampingFraction: 0.65), value: state)
//    }
//
//    private var progress: Double {
//        guard totalDuration > 0 else { return 0 }
//        return timeRemaining / totalDuration
//    }
//}

// MARK: - Compact Rest Timer

struct CompactRestTimer: View {
    let timeRemaining: TimeInterval
    let totalDuration: TimeInterval
    let formattedTime: String
    let onSkip: () -> Void
    let onExpand: () -> Void

    var body: some View {
        HStack(spacing: 5) {
            // Circular progress indicator - smaller
            ZStack {
                Circle()
                    .stroke(Color.gray.opacity(0.3), lineWidth: 2.5)

                Circle()
                    .trim(from: 0, to: progress)
                    .stroke(Color.yellow, style: StrokeStyle(lineWidth: 2.5, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                    .animation(.linear(duration: 1), value: progress)
            }
            .frame(width: 20, height: 20)

            // Timer text - no icon to save space
            Text(formattedTime)
                .font(.system(size: 14, design: .rounded).monospacedDigit())
                .foregroundStyle(.primary)

            Spacer()

            // Expand chevron
            Image(systemName: "chevron.up")
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(.tertiary)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 5)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(.ultraThinMaterial.opacity(0.95))
                .shadow(color: .black.opacity(0.2), radius: 4, y: -1)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .strokeBorder(Color.yellow.opacity(0.3), lineWidth: 1)
        )
        .contentShape(Rectangle())
        .onTapGesture {
            WKInterfaceDevice.current().play(.click)
            onExpand()
        }
        .onLongPressGesture(minimumDuration: 0.5) {
            WKInterfaceDevice.current().play(.success)
            onSkip()
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Rest timer, \(formattedTime) remaining")
        .accessibilityHint("Tap to expand timer. Long press to skip rest.")
    }

    private var progress: Double {
        guard totalDuration > 0 else { return 0 }
        return timeRemaining / totalDuration
    }
}

struct NewShrinkingRestTimer: View {
    let timeRemaining: Double
    let totalDuration: Double
    let onExpand: () -> Void
    let onSkip: () -> Void

    @State private var pulse = false

    let totalWidth: CGFloat = 30

    var body: some View {
        HStack(spacing: 6) {

            ZStack {

                // --- BACKGROUND CAPSULE ---
                Capsule()
                    .fill(.black.opacity(0.15))
                    .overlay(
                        Capsule()
                            .stroke(.white.opacity(0.10), lineWidth: 0.8)
                    )

                // --- SMOOTH REMAINING BAR ---
                ZStack(alignment: .leading) {

                    // The shrinking bar, scaled smoothly
                    Capsule()
                        .fill(gradientFill)
                        .scaleEffect(x: smoothProgress, y: 1, anchor: .leading)
                        .animation(.easeInOut(duration: 0.35), value: smoothProgress)

                    // Trailing fade: makes the shrink edge appear soft
//                    Rectangle()
//                        .fill(fadeGradient)
//                        .frame(width: 14)
//                        .offset(x: barWidth - 14)
//                        .opacity(smoothProgress > 0 ? 1 : 0)
//                        .allowsHitTesting(false)

                    // Soft glow at the leading edge
//                    Circle()
//                        .fill(Color.yellow.opacity(0.5))
//                        .frame(width: 14, height: 14)
//                        .offset(x: barWidth - 7)    // center at trailing edge
//                        .blur(radius: 4)
//                        .opacity(smoothProgress > 0 ? 1 : 0)
                }

                // GPU-MASK to prevent any pixel bleeding
                .mask(Capsule())

                // --- TIME LABEL ---
                Text(formattedTime)
                    .font(.system(size: 13, weight: .medium, design: .rounded).monospacedDigit())
                    .foregroundStyle(.primary)
                    .shadow(radius: 0.5)
            }
            .frame(width: totalWidth, height: 15)
            .scaleEffect(pulse ? 1.06 : 1.00)
            .animation(pulseAnimation, value: pulse)
            .onChange(of: timeRemaining) { _ in
                if timeRemaining <= 3 { pulse = true }
            }

            // Chevron icon
            Image(systemName: "chevron.up")
                .font(.system(size: 10, weight: .bold))
                .foregroundStyle(.tertiary)
        }

        // --- CONTAINER CARD STYLE ---
        .padding(.horizontal, 5)
        .padding(.vertical, 5)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(.ultraThinMaterial.opacity(0.95))
                .shadow(color: .black.opacity(0.25), radius: 4, y: -1)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 18)
                .stroke(Color.white.opacity(0.12), lineWidth: 1)
        )
        .contentShape(Rectangle())
        .onTapGesture {
            WKInterfaceDevice.current().play(.click)
            onExpand()
        }
        .onLongPressGesture(minimumDuration: 0.5) {
            WKInterfaceDevice.current().play(.success)
            onSkip()
        }
    }

    // MARK: - Computed Properties

    private var smoothProgress: CGFloat {
        guard totalDuration > 0 else { return 0 }
        return CGFloat(timeRemaining / totalDuration)
    }

    private var barWidth: CGFloat {
        totalWidth * smoothProgress   // matches the frame width of the capsule
    }

    private var formattedTime: String {
        let seconds = Int(timeRemaining)
        return String(format: "%02d", seconds)
    }

    private var gradientFill: LinearGradient {
        LinearGradient(
            colors: [
                Color.yellow.opacity(0.90),
                Color.yellow.opacity(0.55)
            ],
            startPoint: .leading,
            endPoint: .trailing
        )
    }

    // A smooth trailing fade so the bar doesn’t end sharply
    private var fadeGradient: LinearGradient {
        LinearGradient(
            colors: [
                Color.yellow.opacity(0.40),
                Color.yellow.opacity(0.05),
                .clear
            ],
            startPoint: .leading,
            endPoint: .trailing
        )
    }

    // Pulse effect for the last 3 seconds
    private var pulseAnimation: Animation {
        .easeInOut(duration: 0.6).repeatForever(autoreverses: true)
    }
}

struct ShrinkingRestTimer: View {
    let timeRemaining: Double
    let totalDuration: Double
    let onExpand: () -> Void
    let onSkip: () -> Void

    @State private var pulse = false

    var body: some View {
        HStack(spacing: 6) {

            ZStack {
                GeometryReader { geo in
                    ZStack(alignment: .leading) {

                        // Background capsule track
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .fill(.black.opacity(0.15))

                        // Remaining bar
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .fill(gradientFill)
                            .frame(width: geo.size.width * progress)
                            .animation(.easeInOut(duration: 0.3), value: progress)

                        // Subtle glossy highlight (premium)
                        RoundedRectangle(cornerRadius: 12)
                            .fill(.white.opacity(0.10))
                            .blur(radius: 1)
                    }
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                }
//                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .stroke(Color.white.opacity(0.12), lineWidth: 0.8)
                )
                .frame(width: 62, height: 24)

                // Time text stays centered and readable
                Text(formattedTime)
                    .font(.system(size: 13, weight: .medium, design: .rounded).monospacedDigit())
                    .foregroundStyle(.primary)
                    .shadow(radius: 0.5)
            }
            .scaleEffect(pulse ? 1.06 : 1.00)
            .animation(pulseAnimation, value: pulse)
            .onChange(of: timeRemaining) { _ in
                if timeRemaining <= 3 { pulse = true }
            }

            Image(systemName: "chevron.up")
                .font(.system(size: 10, weight: .bold))
                .foregroundStyle(.tertiary)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 5)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(.ultraThinMaterial.opacity(0.95))
                .shadow(color: .black.opacity(0.25), radius: 4, y: -1)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 18)
                .stroke(Color.white.opacity(0.12), lineWidth: 1)
        )
        .contentShape(Rectangle())
        .onTapGesture {
            WKInterfaceDevice.current().play(.click)
            onExpand()
        }
        .onLongPressGesture(minimumDuration: 0.5) {
            WKInterfaceDevice.current().play(.success)
            onSkip()
        }
    }

    // MARK: - Helpers

    private var progress: CGFloat {
        guard totalDuration > 0 else { return 0 }
        return CGFloat(timeRemaining / totalDuration)
    }

    private var formattedTime: String {
        let seconds = Int(timeRemaining)
        return String(format: "%02d", seconds)
    }

    private var gradientFill: LinearGradient {
        LinearGradient(
            colors: [
                Color.yellow.opacity(0.8),
                Color.yellow.opacity(0.55)
            ],
            startPoint: .leading,
            endPoint: .trailing
        )
    }

    private var pulseAnimation: Animation {
        .easeInOut(duration: 0.6).repeatForever(autoreverses: true)
    }
}

//
//#Preview("Running") {
//    RestTimerView(
//        timeRemaining: 45,
//        totalDuration: 90,
//        formattedTime: "0:45",
//        state: .running,
//        onSkip: { },
//        onMinimize: { }
//    )
//}
//
//#Preview("Completed") {
//    RestTimerView(
//        timeRemaining: 0,
//        totalDuration: 90,
//        formattedTime: "0:00",
//        state: .completed,
//        onSkip: { },
//        onMinimize: { }
//    )
//}
