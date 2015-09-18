/// A 'Future' holds a result: Result<T,E>? that can be, eventually, available at a certain time
/// Once the Future is completed, its value can't change any further
/// The Future state could be 'not completed', thus result == nil, or 'completed', thus result != nil and can be .Success or .Failure
/// Various callback methods can inform client that a Future is in state 'completed'

import Foundation
import Result
import Queue
import Elements

///MARK: - basic definitions
final public class Future<T,E> {
    
    ///  'result' is an exposed, non-mutable, computed property that refers to the invisible, private var result_internal; this construct is necessary because 'result' should be able to mutate over time, but shouldn't be mutated by clients
    private var result_internal: Result<T,E>? = nil
    public var result: Result<T,E>? {
        return result_internal
    }
    
    /// useful typealias to represent a generic task that returns a Result
    public typealias Task = () -> Result<T,E>
    
    /// the designated init method accepts a Task, and a Queue to execute the task
    public init(queue: Queue, _ task: Task?) {
        if let actualTask = task {
            queue.async { () -> () in
                let result = actualTask()
                Queue.main.async { () -> () in
                    self.complete(result)
                    return
                }
            }
        }
    }
    
    /// a convenience init method only accepts the task, and considers the generic global queue
    public convenience init(_ task: Task?) {
        self.init(queue: Queue.global, task)
    }
    
    /// a convenience empty init method doesn't associate any predefined task to the future, and it's used by Promise to manually complete the Future
    public convenience init() {
        self.init(nil)
    }
    
    /// convenience computed property, to check is the current state is 'completed' or not
    public var isCompleted: Bool {
        return self.result_internal != nil
    }
    
    /// some typealiases to conveniently define the various kinds of callbacks
    public typealias CompletionCallback = Result<T,E> -> ()
    public typealias SuccessCallback = T -> ()
    public typealias FailureCallback = E -> ()
    
    /// all callbacks are actually wrapped in a single kind of internal callback, and then are collected in a single array for execution
    private typealias CallbackInternal = (future: Future<T,E>) -> ()
    private var callbacks: [CallbackInternal] = Array<CallbackInternal>()
    func runCallbacks() {
        /// all callbacks are collected in an immutable array before calling, and the mutable version is cleaned
        let currentCallbacks = callbacks.map { $0 }
        callbacks.removeAll()
        for callback in currentCallbacks {
            callback(future: self)
        }
        
        /// if there's still some callback to call (because during the for cycle some callback was added to 'callbacks'), the function is called again
        if (callbacks.count > 0) {
            runCallbacks()
        }
    }
    
    /// all callbacks are executed on a background, serial queue
    let callbackExecutionQueue = Queue(dispatch_queue_create("callbackExecutionQueue", DISPATCH_QUEUE_SERIAL))
    
    /// the 'onComplete' method creates an internal callback and adds it to the callbacks array, or directly runs the callback if 'isCompleted == true'
    public func onComplete(callback: CompletionCallback) -> Future {
        if let result = result {
            callback(result)
        }
        else {
            let callbackInternal: CallbackInternal = { future in
                future.callbackExecutionQueue.sync {
                    if let result = future.result {
                        callback(result)
                    }
                }
            }
            callbacks.append(callbackInternal)
        }
        return self
    }
    
    /// the 'onSuccess' and 'onFailure' methods are convenience methods that call the 'onComplete' method with a CompletionCallback that actually calls the input callback exclusively if Result is respectively .Success or .Failure
    public func onSuccess(callback: SuccessCallback) -> Future {
        onComplete { result in
            switch result {
            case .Success(let value):
                callback(value)
            default:
                break
            }
        }
        return self
    }
    public func onFailure(callback: FailureCallback) -> Future {
        onComplete { result in
            switch result {
            case .Failure(let value):
                callback(value)
            default:
                break
            }
        }
        return self
    }
}

extension Future {
    /// the 'complete' method completes the future by assigning a value to 'result' and then running callbacks
    /// the method returns a Bool because the future will be completed excusively if its state is 'not completed' (that is, self.result_internal == nil)
    /// the method is internal: a Future provider should use the Promise interface to complete a Future
    func complete(result: Result<T,E>) -> Bool {
        if isCompleted {
            return false
        }
        else {
            result_internal = result
            runCallbacks()
            return true
        }
    }
}

extension Future {

    public func map <U> (change: T -> U) -> Future<U,E> {
        let newFuture = Future<U,E>()
        onComplete { result in
            switch result {
            case .Success(let value):
                newFuture.complete(Result.success(change(value)))
            case .Failure(let error):
                newFuture.complete(Result.failure(error))
            }
        }
        return newFuture
    }
    
    public func flatMap <U> (change: T -> Future<U,E>) -> Future<U,E> {
        let newFuture = Future<U,E>()
        onComplete { result in
            switch result {
            case .Success(let value):
                change(value).onComplete { newFuture.complete($0) }
            case .Failure(let error):
                newFuture.complete(Result.failure(error))
            }
        }
        return newFuture
    }
    
    public func zip <U> (other: Future<U,E>) -> Future<(T,U),E> {
        return flatMap { value -> Future<(T,U),E> in
            return other.map { otherValue in
                return (value, otherValue)
            }
        }
    }
}

///MARK: - 'Applicative' and 'Monad' definitions

public func pure <A,E> (value: A) -> Future<A,E> {
    return fulfilled(value)
}

public func <*> <A,B,E> (lhs: Future<A->B,E>, rhs: Future<A,E>) -> Future<B,E> {
    return lhs.zip(rhs).map { change, value in
        return change(value)
    }
}

public func <^> <A,B,E> (lhs: A->B, rhs: Future<A,E>) -> Future<B,E> {
    return pure(lhs) <*> rhs
}

public func >>- <T,U,E> (lhs: Future<T,E>, rhs: T->Future<U,E>) -> Future<U,E> {
    return lhs.flatMap(rhs)
}
