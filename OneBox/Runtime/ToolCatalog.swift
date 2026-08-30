@MainActor
public struct ToolCatalog {
    public let registrations: [ToolRegistration]

    public init(registrations: [ToolRegistration]) {
        precondition(
            Set(registrations.map(\.id)).count == registrations.count,
            "Tool registrations must use unique IDs."
        )
        self.registrations = registrations
    }

    public func registration(for id: ToolID?) -> ToolRegistration? {
        registrations.first { $0.id == id }
    }

    public func prepareForApplicationTermination() async {
        let tasks = registrations.map { registration in
            Task { @MainActor in
                await registration.prepareForApplicationTermination()
            }
        }
        await withTaskCancellationHandler {
            for task in tasks {
                await task.value
            }
        } onCancel: {
            for task in tasks {
                task.cancel()
            }
        }
    }
}
