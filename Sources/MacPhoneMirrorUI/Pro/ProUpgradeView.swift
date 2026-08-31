import SwiftUI
import MacPhoneMirrorCore

public struct ProUpgradeView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var licenseKeyInput = ""
    @State private var isUnlocking = false
    @State private var unlockSuccess = false
    @State private var errorMessage: String?
    
    public init() {}
    
    public var body: some View {
        VStack(spacing: 24) {
            // Header Hero
            VStack(spacing: 8) {
                ZStack {
                    Circle()
                        .fill(
                            LinearGradient(colors: [.indigo, .purple, .pink], startPoint: .topLeading, endPoint: .bottomTrailing)
                        )
                        .frame(width: 64, height: 64)
                    Image(systemName: "crown.fill")
                        .font(.system(size: 30))
                        .foregroundColor(.white)
                }
                
                Text("Upgrade to MacPhoneMirror Pro")
                    .font(.title.bold())
                Text("Unlock full Bluetooth HID control, 60 FPS ultra quality, recording, and custom titanium finishes.")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 440)
            }
            
            // Feature Grid
            VStack(spacing: 12) {
                ForEach(Feature.allCases.filter { $0.isProOnly }) { feature in
                    HStack(spacing: 12) {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundColor(.green)
                            .font(.system(size: 16))
                        
                        VStack(alignment: .leading, spacing: 2) {
                            Text(feature.rawValue).font(.headline)
                            Text(feature.description).font(.caption).foregroundColor(.secondary)
                        }
                        Spacer()
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 8)
                    .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(Color.primary.opacity(0.04)))
                }
            }
            .frame(maxHeight: 220)
            
            Divider()
            
            // License Entry
            VStack(spacing: 12) {
                HStack {
                    TextField("Enter License Key (e.g. MPM-PRO-2026)", text: $licenseKeyInput)
                        .textFieldStyle(.roundedBorder)
                    
                    Button("Activate Pro") {
                        Task {
                            isUnlocking = true
                            let ok = await LocalEntitlementProvider.shared.unlockPro(licenseKey: licenseKeyInput)
                            isUnlocking = false
                            if ok {
                                unlockSuccess = true
                                DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) {
                                    dismiss()
                                }
                            } else {
                                errorMessage = "Please enter a valid license key."
                            }
                        }
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(licenseKeyInput.isEmpty || isUnlocking)
                }
                
                if let error = errorMessage {
                    Text(error)
                        .font(.caption)
                        .foregroundColor(.red)
                }
                
                if unlockSuccess {
                    Text("✓ MacPhoneMirror Pro Activated!")
                        .font(.caption.bold())
                        .foregroundColor(.green)
                }
            }
        }
        .padding(28)
        .frame(width: 560, height: 600)
    }
}
