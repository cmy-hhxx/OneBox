import OneBoxRuntime

public enum BlogListenModule {
    public static let id = ToolID(rawValue: "blog-listen")

    public static let registration = ToolRegistration(
        id: id,
        displayName: "博客收听"
    ) { _ in
        BlogListenView()
    }
}
