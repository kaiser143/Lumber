import SwiftUI

struct LumberIcon: View {
    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 112, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [Color(red: 1, green: 0.71, blue: 0.37), Color(red: 0.91, green: 0.25, blue: 0.18)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )

            ZStack(alignment: .topTrailing) {
                UnevenRoundedRectangle(
                    topLeadingRadius: 18,
                    bottomLeadingRadius: 18,
                    bottomTrailingRadius: 18,
                    topTrailingRadius: 4
                )
                .fill(
                    LinearGradient(
                        colors: [Color(red: 1, green: 0.99, blue: 0.96), Color(red: 1, green: 0.9, blue: 0.79)],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
                .overlay(alignment: .topTrailing) {
                    Path { path in
                        path.move(to: CGPoint(x: 0, y: 0))
                        path.addLine(to: CGPoint(x: 0, y: 42))
                        path.addLine(to: CGPoint(x: 42, y: 42))
                        path.closeSubpath()
                    }
                    .fill(Color(red: 1, green: 0.83, blue: 0.65))
                    .frame(width: 42, height: 42)
                }

                VStack(alignment: .leading, spacing: 15) {
                    Capsule().fill(Color(red: 0.89, green: 0.62, blue: 0.44)).frame(width: 98, height: 10)
                    Capsule().fill(Color(red: 0.89, green: 0.62, blue: 0.44)).frame(width: 74, height: 10)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                .padding(.leading, 24)
                .padding(.top, 76)
            }
            .frame(width: 174, height: 210)
            .offset(x: -19, y: -15)
            .shadow(color: Color(red: 0.48, green: 0.16, blue: 0.1).opacity(0.2), radius: 9, y: 7)

            ZStack {
                Circle()
                    .fill(Color(red: 0.84, green: 0.25, blue: 0.18))
                Circle()
                    .stroke(Color(red: 1, green: 0.87, blue: 0.68), lineWidth: 6)
                    .padding(10)
                Circle()
                    .fill(Color(red: 1, green: 0.98, blue: 0.92))
                    .frame(width: 12, height: 12)
            }
            .frame(width: 112, height: 112)
            .overlay(alignment: .bottomTrailing) {
                Capsule()
                    .fill(Color(red: 1, green: 0.98, blue: 0.92))
                    .frame(width: 48, height: 16)
                    .rotationEffect(.degrees(48))
                    .offset(x: 22, y: 16)
            }
            .offset(x: 21, y: 26)
            .shadow(color: Color(red: 0.48, green: 0.16, blue: 0.1).opacity(0.22), radius: 8, y: 5)

            Image(systemName: "plus")
                .font(.system(size: 20, weight: .bold))
                .foregroundStyle(Color.white.opacity(0.95))
                .offset(x: 82, y: -82)
        }
        .frame(width: 256, height: 256)
        .clipShape(RoundedRectangle(cornerRadius: 58, style: .continuous))
    }
}
