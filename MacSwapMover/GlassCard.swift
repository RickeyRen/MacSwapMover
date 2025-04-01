import SwiftUI

struct GlassCard<Content: View>: View {
    var content: Content
    var cornerRadius: CGFloat = 12
    var padding: CGFloat = 16
    
    init(cornerRadius: CGFloat = 12, padding: CGFloat = 16, @ViewBuilder content: () -> Content) {
        self.content = content()
        self.cornerRadius = cornerRadius
        self.padding = padding
    }
    
    var body: some View {
        content
            .padding(padding)
            .background(
                RoundedRectangle(cornerRadius: cornerRadius)
                    .fill(Color(.windowBackgroundColor).opacity(0.7))
                    .background(
                        RoundedRectangle(cornerRadius: cornerRadius)
                            .stroke(Color.white.opacity(0.2), lineWidth: 1)
                    )
                    .shadow(color: Color.black.opacity(0.05), radius: 5, x: 0, y: 2)
                    .shadow(color: Color.black.opacity(0.025), radius: 10, x: 0, y: 4)
            )
    }
}

struct GlassCard_Previews: PreviewProvider {
    static var previews: some View {
        ZStack {
            Color.gray.opacity(0.2).edgesIgnoringSafeArea(.all)
            
            GlassCard {
                Text("Glass Card Content")
                    .foregroundColor(.primary)
            }
            .frame(width: 300, height: 200)
        }
    }
} 