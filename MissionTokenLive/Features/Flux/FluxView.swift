import SwiftUI

/// Vue commune de l’activité, des agents et des sessions observées.
struct FluxView: View {
    @EnvironmentObject private var store: AppStore

    var body: some View {
        WorkTree3DView(tree: store.worktree, software: store.snapshot.software)
    }
}
