import SwiftUI

struct FavoritesScreen: View {
    var body: some View {
        AccountVideoListScreen(
            kind: .favorites,
            title: "收藏",
            emptyTitle: "收藏暂无内容",
            loginMessage: "登录后可查看喜欢的影片。"
        )
    }
}
