/// A 'Promise' is an object that contains an empty Future: usually the Promise is created by a server, and the server provides clients with the Promise's Future. Then, when the server is done with the computations, the Promise is 'fulfilled' and the Future is completed; obviously, clients only see the Future
/// A Promise can be considered the 'writable' part of a Future

import Foundation
import Swiftz

public class Promise<T,E> {
    public let future: Future<T,E>
    
    public init() {
        self.future = Future<T,E>()
    }
    
    public func complete(result: Either<E,T>) {
        future.complete(result)
    }
    
    /// the method 'completeWith' completes the current future with the result obtained by the completion of another Future
    public func completeWith(future: Future<T,E>) {
        future.onComplete { result in
            self.complete(result)
        }
    }
}

/// the func 'completed' returns an already completed Future: useful for using functions that require Futures as input in situations in which the data is ready
public func completed <T,E> (result: Either<E,T>) -> Future<T,E> {
    let promise = Promise<T,E>()
    promise.complete(result)
    return promise.future
}

/// the func 'fulfilled' already completed Future that contains a successful Result
public func fulfilled <T,E> (value: T) -> Future<T,E> {
    let promise = Promise<T,E>()
    promise.complete(Either<E,T>.Right(value))
    return promise.future
}

/// 'unfulfilled' does the same with an error
public func unfulfilled <T,E> (error: E) -> Future<T,E> {
    let promise = Promise<T,E>()
    promise.complete(Either.Left(error))
    return promise.future
}