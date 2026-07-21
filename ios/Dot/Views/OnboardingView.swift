import SwiftUI

/// First-launch coach marks: what Dot is, how to pair Wi‑Fi, how to use the gallery.
struct OnboardingView: View {
    var onFinished: () -> Void

    @State private var page = 0
    @State private var iconPulse = false

    private let slides: [OnboardingSlide] = [
        OnboardingSlide(
            symbol: "circle.hexagongrid.circle.fill",
            title: "Это Dot",
            body: "Приложение управляет круглым экраном в машине: выбираете анимацию или своё фото — и оно сразу появляется на дисплее."
        ),
        OnboardingSlide(
            symbol: "wifi",
            title: "Первое подключение",
            body: "Подключите iPhone к Wi‑Fi Dot-Setup-… (пароль dotsetup1), откройте настройку Wi‑Fi в приложении и введите имя и пароль Режима модема. Терминал на Dot не нужен."
        ),
        OnboardingSlide(
            symbol: "iphone.and.arrow.forward",
            title: "Обычный день",
            body: "Включите Режим модема — Dot подключится сам. В галерее выберите картинку и нажмите Apply. Свои фото — во вкладке Custom."
        ),
    ]

    var body: some View {
        ZStack {
            LinearGradient(
                colors: [
                    Color(red: 0.07, green: 0.09, blue: 0.12),
                    Color(red: 0.12, green: 0.16, blue: 0.22),
                    Color(red: 0.08, green: 0.11, blue: 0.14),
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .ignoresSafeArea()

            Circle()
                .fill(Color(red: 0.35, green: 0.55, blue: 0.75).opacity(0.18))
                .frame(width: 320, height: 320)
                .blur(radius: 40)
                .offset(x: 110, y: -220)
                .allowsHitTesting(false)

            VStack(spacing: 0) {
                HStack {
                    Spacer()
                    if page < slides.count - 1 {
                        Button("Пропустить") {
                            finish()
                        }
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(.white.opacity(0.7))
                        .padding(.trailing, 20)
                        .padding(.top, 12)
                    }
                }
                .frame(height: 44)

                // Manual slides (not TabView) so «Далее» is never eaten by page gestures.
                ZStack {
                    ForEach(Array(slides.enumerated()), id: \.offset) { index, slide in
                        slidePage(slide, index: index)
                            .opacity(page == index ? 1 : 0)
                            .allowsHitTesting(page == index)
                            .accessibilityHidden(page != index)
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .gesture(
                    DragGesture(minimumDistance: 40)
                        .onEnded { value in
                            let dx = value.translation.width
                            if dx < -40, page < slides.count - 1 {
                                withAnimation(.easeInOut(duration: 0.28)) { page += 1 }
                            } else if dx > 40, page > 0 {
                                withAnimation(.easeInOut(duration: 0.28)) { page -= 1 }
                            }
                        }
                )

                pageDots
                    .padding(.bottom, 20)

                Button(action: advance) {
                    Text(page < slides.count - 1 ? "Далее" : "Начать")
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 16)
                        .foregroundStyle(Color(red: 0.07, green: 0.09, blue: 0.12))
                        .background(Color.white, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                        .contentShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                }
                .buttonStyle(.plain)
                .padding(.horizontal, 24)
                .padding(.bottom, 36)
            }
        }
        .preferredColorScheme(.dark)
    }

    private func advance() {
        if page < slides.count - 1 {
            withAnimation(.easeInOut(duration: 0.28)) {
                page += 1
            }
        } else {
            finish()
        }
    }

    private func slidePage(_ slide: OnboardingSlide, index: Int) -> some View {
        VStack(spacing: 28) {
            Spacer(minLength: 24)

            ZStack {
                Circle()
                    .strokeBorder(Color.white.opacity(0.12), lineWidth: 1)
                    .frame(width: 132, height: 132)
                Image(systemName: slide.symbol)
                    .font(.system(size: 56, weight: .light))
                    .foregroundStyle(.white)
                    .opacity(page == index && iconPulse ? 1 : 0.72)
                    .scaleEffect(page == index && iconPulse ? 1.04 : 1)
            }
            .scaleEffect(page == index ? 1 : 0.92)
            .animation(.spring(response: 0.45, dampingFraction: 0.78), value: page)
            .onAppear {
                guard page == index else { return }
                withAnimation(.easeInOut(duration: 1.1).repeatForever(autoreverses: true)) {
                    iconPulse = true
                }
            }
            .onChange(of: page) { newPage in
                iconPulse = false
                guard newPage == index else { return }
                withAnimation(.easeInOut(duration: 1.1).repeatForever(autoreverses: true)) {
                    iconPulse = true
                }
            }

            VStack(spacing: 10) {
                Text(slide.title)
                    .font(.title2.weight(.semibold))
                    .foregroundStyle(.white)
                    .multilineTextAlignment(.center)

                Text(slide.body)
                    .font(.body)
                    .foregroundStyle(.white.opacity(0.78))
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal, 8)
            }
            .padding(.horizontal, 28)

            Spacer(minLength: 24)
        }
    }

    private var pageDots: some View {
        HStack(spacing: 8) {
            ForEach(0..<slides.count, id: \.self) { index in
                Capsule()
                    .fill(index == page ? Color.white : Color.white.opacity(0.28))
                    .frame(width: index == page ? 22 : 8, height: 8)
                    .animation(.spring(response: 0.35, dampingFraction: 0.8), value: page)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Слайд \(page + 1) из \(slides.count)")
    }

    private func finish() {
        onFinished()
    }
}

private struct OnboardingSlide {
    let symbol: String
    let title: String
    let body: String
}

#Preview {
    OnboardingView(onFinished: {})
}
