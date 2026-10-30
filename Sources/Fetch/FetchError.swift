/// What `fetch` and a response's body fail with: the TypeError the Fetch API
/// throws, for a request it cannot make or a network error, with its message.
public enum FetchError: Error, Equatable, Sendable {
    case typeError(String)
}
