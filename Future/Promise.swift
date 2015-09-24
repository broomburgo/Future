/// A 'Promise' is an object that contains an empty Future: usually the Promise is created by a server, and the server provides clients with the Promise's Future. Then, when the server is done with the computations, the Promise is 'fulfilled' and the Future is completed; obviously, clients only see the Future
/// A Promise can be considered the 'writable' part of a Future

import Foundation
import Swiftz

public class Promise<E,T>
{
  public let future: Future<E,T>
  
  public init()
  {
    self.future = Future<E,T>()
  }
  
  public func complete (result: Either<E,T>) -> Promise<E,T>
  {
    future.complete(result)
    return self
  }
  
  /// the method 'completeWith' completes the current future with the result obtained by the completion of another Future
  public func completeWith (future: Future<E,T>) -> Promise<E,T>
  {
    future.onComplete { [unowned self] result in self.complete(result) }
    return self
  }
  
  /// the func 'completed' returns an already completed Future: useful for using functions that require Futures as input in situations in which the data is ready
  public static func completed (result: Either<E,T>) -> Future<E,T>
  {
    return Promise<E,T>().complete(result).future
  }
  
  /// the func 'fulfilled' already completed Future that contains a successful Result
  public static func fulfilled (value: T) -> Future<E,T>
  {
    return Promise<E,T>().complete(Either<E,T>.Right(value)).future
  }
  
  /// 'unfulfilled' does the same with an error
  public static func unfulfilled <E,T> (error: E) -> Future<E,T>
  {
    return Promise<E,T>().complete(Either<E,T>.Left(error)).future
  }
}

