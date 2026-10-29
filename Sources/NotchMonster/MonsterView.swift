import SwiftUI

struct MonsterView: View {
    @Bindable var model: MonsterModel
    var screenFrame: CGRect? = nil
    @State private var reach = CGSize.zero
    @State private var direction = CGSize(width: 0, height: -1)
    @State private var extensionAmount: CGFloat = 0
    @State private var gripAmount: CGFloat = 0

    private var isShowing: Bool {
        model.enabled && [.curious, .reaching, .chewing].contains(model.mood) && model.proximity > 0.05
    }

    private var idlePose: IdleArmPose? {
        guard model.enabled, let pose = model.idleArm,
              screenFrame == nil || screenFrame == pose.screenFrame else { return nil }
        return pose
    }

    var body: some View {
        PuppetArm(reach: idlePose?.reach ?? reach,
                  direction: idlePose?.reach ?? direction,
                  extensionAmount: idlePose?.extensionAmount ?? extensionAmount,
                  gripAmount: idlePose == nil ? gripAmount : 0)
            .onChange(of: isShowing, initial: true) { _, showing in
                if showing {
                    followCursor()
                    gripAmount = model.mood == .chewing ? 1 : 0
                }
                withAnimation(model.reduceMotion ? nil : .linear(duration: 0.07)) {
                    extensionAmount = showing ? 1 : 0
                }
            }
            .onChange(of: model.cursorOffset) { _, _ in
                if isShowing { followCursor() }
            }
            .onChange(of: model.mood) { _, mood in
                if mood == .chewing {
                    // Lock the wrist and arm angle for the entire straight yank.
                    // The only articulation is the fingers closing at the grip.
                    reach = model.cursorOffset
                    if hypot(reach.width, reach.height) > 1 { direction = reach }
                    extensionAmount = 1
                    withAnimation(model.reduceMotion ? nil : .linear(duration: 0.045)) {
                        gripAmount = 1
                    }
                } else if isShowing {
                    gripAmount = 0
                }
            }
            .allowsHitTesting(false)
    }

    private func followCursor() {
        reach = model.cursorOffset
        if model.mood != .chewing, hypot(reach.width, reach.height) > 1 {
            direction = reach
        }
    }
}
