import OneBoxRuntime

@MainActor
public enum BlogListenModule {
    public static let id = ToolID(rawValue: "blog-listen")

    public static let registration = ToolRegistration(
        id: id,
        displayName: "博客收听"
    ) {
        BlogListenView()
    }
}
