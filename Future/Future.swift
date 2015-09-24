/// A 'Future' holds a result: Either<E,T>? that can be, eventually, available at a certain time
/// Once the Future is completed, its value can't change any further
/// The Future state could be '.Working', or '.Done' with a result that can be .Right or .Left
/// Various callback methods can inform client that a Future is in state '.Done'

import Foundation
import Queue
import Swiftz

public enum FutureState<E,T>
{
  case Working
  case Done(Either<E,T>)
}

///MARK: - basic definitions
final public class Future<E,T>
{
  /// 'state' is not exposed: clients should communicate with a Future with onComplete, onSuccess and onFailure methods;
  /// that means that no client should expect a synchronous execution for 'on' methods
  private var state = FutureState<E,T>.Working
  
  /// useful typealias to represent a generic task that returns a Either
  public typealias Task = () -> Either<E,T>
  
  /// the designated init method accepts a Task, and a Queue to execute the task
  public init (queue: Queue, _ optionalTask: Task?) {
    if let
      task = optionalTask
    {
      queue.async {
        let result = task()
        Queue.main.async {
          self.complete(result)
        }
      }
    }
  }
  
  /// a convenience init method only accepts the task, and considers the generic global queue
  public convenience init (_ task: Task?)
  {
    self.init(queue: Queue.global, task)
  }
  
  /// a convenience empty init method doesn't associate any predefined task to the future, and it's used by Promise to manually complete the Future
  public convenience init()
  {
    self.init(nil)
  }
  
  /// some typealiases to conveniently define the various kinds of callbacks
  public typealias CompletionCallback = Either<E,T> -> ()
  public typealias SuccessCallback = T -> ()
  public typealias FailureCallback = E -> ()
  
  /// all callbacks are actually wrapped in a single kind of internal callback, and then are collected in a single array for execution
  private typealias CallbackInternal = Future<E,T> -> ()
  private var callbacks: [CallbackInternal] = Array<CallbackInternal>()
  func runCallbacks()
  {
    /// all callbacks are collected in an immutable array before calling, and the mutable version is cleaned
    let currentCallbacks = callbacks.map { $0 }
    callbacks.removeAll()
    for callback in currentCallbacks
    {
      callback(self)
    }
    
    /// if there's still some callback to call (because during the for cycle some callback was added to 'callbacks'), the function is called again
    if callbacks.count > 0
    {
      runCallbacks()
    }
  }
  
  /// all callbacks are executed on a background, serial queue
  let callbackExecutionQueue = Queue(dispatch_queue_create("callbackExecutionQueue", DISPATCH_QUEUE_SERIAL))
  
  /// the 'onComplete' method creates an internal callback and adds it to the callbacks array, or directly runs the callback if '.Done'
  public func onComplete (callback: CompletionCallback) -> Future
  {
    switch state
    {
    case .Done(let result):
      callback(result)
    case .Working:
      callbacks.append { $0.onComplete(callback) }
    }
    return self
  }
  
  /// the 'onSuccess' and 'onFailure' methods are convenience methods that call the 'onComplete' method with a CompletionCallback that actually calls the input callback exclusively if Either is respectively .Right or .Left
  public func onSuccess (callback: SuccessCallback) -> Future
  {
    onComplete { result in
      switch result
      {
      case .Right(let value):
        callback(value)
      case .Left:
        break
      }
    }
    return self
  }
  
  public func onFailure (callback: FailureCallback) -> Future
  {
    onComplete { result in
      switch result
      {
      case .Left(let value):
        callback(value)
      default:
        break
      }
    }
    return self
  }
}

extension Future
{
  /// the 'complete' internal method completes the future by assigning a value to 'state' and then running callbacks
  /// the method returns a Bool because the future will be completed excusively if its state is '.Working'
  /// the method is internal: a Future provider should use the Promise interface to complete a Future
  func complete (result: Either<E,T>) -> Bool
  {
    switch state
    {
    case .Working:
      state = .Done(result)
      runCallbacks()
      return true
    case .Done:
      return false
    }
  }
}

extension Future
{
  public func map <U> (change: T -> U) -> Future<E,U>
  {
    let newFuture = Future<E,U>()
    onComplete {
      switch $0
      {
      case .Right(let value):
        newFuture.complete § Either.Right § change § value
      case .Left(let error):
        newFuture.complete § Either.Left § error
      }
    }
    return newFuture
  }
  
  public func flatMap <U> (change: T -> Future<E,U>) -> Future<E,U>
  {
    let newFuture = Future<E,U>()
    onComplete {
      switch $0
      {
      case .Right(let value):
        change(value).onComplete { newFuture.complete($0) }
      case .Left(let error):
        newFuture.complete § Either.Left § error
      }
    }
    return newFuture
  }
  
  public func zip <U> (other: Future<E,U>) -> Future<E,(T,U)>
  {
    return flatMap { value in other.map { otherValue in (value, otherValue) } }
  }
}

///MARK: - 'Applicative' and 'Monad' definitions

public func pure <E,A> (value: A) -> Future<E,A>
{
  let future = Future<E,A>()
  future.complete(Either<E,A>.Right(value))
  return future
}

public func <*> <E,A,B> (lhs: Future<E,A->B>, rhs: Future<E,A>) -> Future<E,B>
{
  return lhs.zip(rhs).map { $0($1) }
}

public func <^> <E,A,B> (lhs: A->B, rhs: Future<E,A>) -> Future<E,B>
{
  return pure(lhs) <*> rhs
}

public func >>- <E,A,B> (lhs: Future<E,A>, rhs: A->Future<E,B>) -> Future<E,B>
{
  return lhs.flatMap(rhs)
}
