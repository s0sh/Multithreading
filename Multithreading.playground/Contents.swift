import UIKit

// MARK: - Thread, pthread_t
/// ================================================================
// Самая низкоуровневая реализация потоков, к которой мы имеем доступ
// - ниже только системная реализация

var thread = pthread_t(bitPattern: 0) // Создаем поток
var attributes = pthread_attr_t() // Создаем аттрибуты для потока

pthread_attr_init(&attributes) // Инициализируем аттрибуты
// Добавляем уровень качества сервисса (QOS) это просто инты UInt32
// тут мы определяем насколько быстро юзеру ножен фидбек от потока
// немедленно/сейчас/позже/можно и не ждать пока/ вообще не важно
pthread_attr_set_qos_class_np(&attributes,
                                QOS_CLASS_USER_INTERACTIVE,
                              //QOS_CLASS_USER_INITIATED,
                              //QOS_CLASS_DEFAULT,
                              //QOS_CLASS_BACKGROUND, тут система может выкинуть поток так как посчитает его не важным
                              //QOS_CLASS_UTILITY,
                              0)
// собственно заводим поток и даем ему задачу в клоужере
// стартует сразу после круглой скобки
pthread_create(&thread,
               &attributes, { (someValue) in
    
    print("Low level pthread_t working...")
    // Тут мы можем переопределить QOS
    pthread_set_qos_class_self_np(QOS_CLASS_BACKGROUND, 0)
    return nil
    
}, nil)


let nsthread = Thread {
    print("Thread working...")
    print("QOS: \(qos_class_self())")
}
// Назначаем качество обслуживания
nsthread.qualityOfService = .background

// Мы можем стартонуть поток, отменить и много чего еще ( как и Operations)
// узнать стэйт или является он главным потоком
nsthread.start()
print(nsthread.isCancelled)
print(nsthread.isExecuting)
print(nsthread.isFinished)
print(nsthread.isMainThread)
print(nsthread.cancel())
/// ================================================================

// MARK: - Synchronization [ cи - Mutex ]
// Работает в 15 раз быстрее чем Obj-C обертки
/* Mutex - блокирует и освобождает объект.
 Поток, который в данный момент не владеет этим
 объектом засыпает до того момента пока объект не
 будет освобожден мьютексом
*/

class ThreadSafe {
    private var mutex = pthread_mutex_t()
    
    init() {
        pthread_mutex_init(&mutex, nil)
    }
    
    func testMethod(job: () -> Void) {
        // На случай, если что-то где-то пойдет не так
        // Мы точно должны освободить поток
        defer {
            pthread_mutex_unlock(&mutex)
        }
        pthread_mutex_lock(&mutex)
        // Soome threadsafe work here
        job() // Тут собственно сама внешняя задача работает
    }
}

var array: [String] = []
var job = ThreadSafe()
job.testMethod {
    array.append("Second thread")
    print("Job done..")
}
print(array)
array.append("First thread")
print(array)

// MARK: - [ NSLock ]

class ThreadSafeLock {
    private var nsLock = NSLock()
    func testMethod(job: () -> Void) {
        defer {
            nsLock.unlock()
        }
        nsLock.lock()
        job()
    }
}
array.append("Second 2 thread")
print(array)

// MARK: - RecurciveLock [POSIX]
class RecurciveMutexTest {
    private var mutex = pthread_mutex_t()
    private var mutexAttribute = pthread_mutexattr_t()
    
    init() {
        pthread_mutexattr_init(&mutexAttribute)
        pthread_mutexattr_settype(&mutexAttribute, PTHREAD_MUTEX_RECURSIVE)
        pthread_mutex_init(&mutex, &mutexAttribute)
    }
    
    func firstTask() {
        defer {
            pthread_mutex_unlock(&mutex)
        }
        pthread_mutex_lock(&mutex)
        taskTwo()
    }
    
    private func taskTwo() {
        defer {
            pthread_mutex_unlock(&mutex)
        }
        pthread_mutex_lock(&mutex)
        print("Finish taskTwo()")
    }
    
}

var testRecurcive = RecurciveMutexTest()
testRecurcive.firstTask()

// Swifty same requrcive approach
let recursiveLock = NSRecursiveLock()

class RequrciveThread: Thread {
    override func main() {
        recursiveLock.lock()
        print("Tread recursive lock - locked")
        callMe()
        defer {
            print("main - uknlocked")
            recursiveLock.unlock()
        }
        print("Exit main")
    }
    
    func callMe() {
        recursiveLock.lock()
        print("callMe - locked")
        defer {
            print("callMe - unlocked")
            recursiveLock.unlock()
        }
        print("exit callMe()")
    }
}

let nsRecurciveLock = RequrciveThread()
nsRecurciveLock.start()
//==========================================

// MARK: - C-Style Condition - POSIX
// Настройка порядка выполнения потоков (очередность доступа к ресурсам)
// через сигналы
var available = false
var condition = pthread_cond_t()
var mutex = pthread_mutex_t()

class ConditionMutexPrinter: Thread {
    
    override init() {
        pthread_mutex_init(&mutex, nil)
        pthread_cond_init(&condition, nil)
    }
    
    override func main() {
        printerMethod()
    }
    
    private func printerMethod() {
        
        defer {
            pthread_mutex_unlock(&mutex)
        }
        
        pthread_mutex_lock(&mutex)
        print("Printer entered")
        while !available {
            pthread_cond_wait(&condition, &mutex)
        }
        
        available = false
        // Do some job here
        print("Value printed here")
    }
}

class ConditionMutexWriter: Thread {
    
    override init() {
        pthread_mutex_init(&mutex, nil)
        pthread_cond_init(&condition, nil)
    }
    
    override func main() {
        writerMethod()
    }
    
    private func writerMethod() {
        
        defer {
            pthread_mutex_unlock(&mutex)
        }
        
        pthread_mutex_lock(&mutex)
        print("Writer entered")
        available = true
        pthread_cond_signal(&condition)
        print("Value wrote  here")
    }
}

let conditionWriter = ConditionMutexWriter()
let conditionPrinter = ConditionMutexPrinter()

//conditionPrinter.start()
//conditionWriter.start()


// MARK: - Swifty-Style Condition
let objectCondition = NSCondition()
var objectAvailable = false

class WriterThread: Thread {
    override func main() {
        objectCondition.lock()
        print("WriterThread - entered")
        objectAvailable = true
        objectCondition.signal()
        objectCondition.unlock()
        print("WriterThread - exited")
    }
}

class PrinterThread: Thread {
    override func main() {
        objectCondition.lock()
        print("PrinterThread - entered")
        while !objectAvailable {
            objectCondition.wait()
        }
        available = false
        objectCondition.unlock()
        print("PrinterThread - exited")
    }
}

let reader = PrinterThread()
let writer = WriterThread()

reader.start()
writer.start()

/* Output
 PrinterThread - entered
 WriterThread - entered
 WriterThread - exited
 PrinterThread - exited
 */

// MARK: - ReadWriteLock, SpinLock (deprecated since ios 10) -> UnfairLock since iOs 10
// Защищаем критическую секцию (Save critical section)
class ReadWriteLock {
    private var lock = pthread_rwlock_t()
    private var attributes = pthread_rwlockattr_t()
    private var criticalSectionProperty = 0
    
    init() {
        pthread_rwlock_init(&lock, &attributes)
    }
    
    var workProperty: Int {
        get {
            pthread_rwlock_wrlock(&lock)
            let temp = criticalSectionProperty
            pthread_rwlock_unlock(&lock)
            return temp
        }
        set {
            pthread_rwlock_wrlock(&lock)
            criticalSectionProperty = newValue
            pthread_rwlock_unlock(&lock)
        }
    }
}

class UnfairLock {
    private var lock = os_unfair_lock_s()
    var array: [Int] = []
    
    func addElement() {
        os_unfair_lock_lock(&lock)
        array.append(500)
        os_unfair_lock_unlock(&lock)
    }
}

// High level sync
class SynchronizationObjc {
    private let lock = NSObject()
    private var array = [Int]()
    
    func worker() {
        objc_sync_enter(lock)
        array.append(999)
        objc_sync_exit(lock)
    }
}

// MARK: - GCD -

// We dont think about threads here We concentrate on tasks instead.
// We have abstract QUEUES or LINES to work with. Threads created by iOs for us
// We have serial & concurrent queues and tasks can be added sync(hronously) & asyn(chronously)

import PlaygroundSupport
PlaygroundPage.current.needsIndefiniteExecution = true

enum Queues {
    
    case serialCustom(String)
    case cuncurentCustom(String)
    case systemGlobal
    case backgroundGlobal
    case userInterative
    case userInitiated
    case utility
    case main
    
    func get() -> DispatchQueue {
        switch self {
        case .utility:
            return DispatchQueue.global(qos: .utility)
        case .serialCustom(let value):
            return DispatchQueue(label: value)
        case .cuncurentCustom(let value):
            return DispatchQueue(label: value, attributes: .concurrent)
        case .systemGlobal:
            return DispatchQueue.global()
        case .backgroundGlobal:
            return DispatchQueue.global(qos: .background)
        case .userInterative:
            return DispatchQueue.global(qos: .userInteractive)
        case .userInitiated:
            return DispatchQueue.global(qos: .userInitiated)
        case .main:
            return DispatchQueue.main
        }
    }
    
    // Before write a code we should decide:
    // 1) Which queue we need to achieve needed result  - global or main (system or custom)
    // 2) Which qos to choose (priority metters)
    // 3) Which method we should use to put task into queue SYNC or ASYNC
    
    // Custom queues
//    private let serialQueue = DispatchQueue(label: "serialQueueTest")
//    private let cuncurrentQueue = DispatchQueue(label: "concurentQueueTest", attributes: .concurrent)
//    // System queues
//    // Global queue has a set of prirorities named QOS (Quality of service)
//    private let systemGlobalQueue = DispatchQueue.global() // Default
//    private let backgroundGlobalQueue = DispatchQueue.global(qos: .background) // very low level
//    private let userInteractiveGlobalQueue = DispatchQueue.global(qos: .userInteractive) // Top level
//    private let userInInitiatedGlobalQueue = DispatchQueue.global(qos: .userInitiated) // Very highg level
//    private let utilityGlobalQueue = DispatchQueue.global(qos: .utility) // Highg level
//
//    // System main queue [UI/Gestures/Hit testing]
//    private let systemSerialQueue = DispatchQueue.main
    
}

//let serialCustomQueue = Queues.get(.serialCustom("my_serial_queue.com.Roman"))()
//serialCustomQueue.sync {
//    print("\(Thread.isMainThread) : \(Thread.current)")
//}

// true : <_NSMainThread: 0x600001dd8140>{number = 1, name = main}


// MARK: - WORK ITEMS -

class DispatchWorkItem1 {
    private let queue = Queues.get(.cuncurentCustom("DispatchWorkItem1"))()
    
    func create() {
        let workItem = DispatchWorkItem {
            print("Started DispatchWorkItem1")
            print(Thread.current)
        }
        
        workItem.notify(queue: .main) {
            print("Finished DispatchWorkItem1")
            print(Thread.current)
        }
        queue.async(execute: workItem)
    }
}

//let dispatchWorkItem1 = DispatchWorkItem1()
//dispatchWorkItem1.create()

/*
 Started DispatchWorkItem1
 <NSThread: 0x60000255ac00>{number = 15, name = (null)}
 Finished DispatchWorkItem1
 <_NSMainThread: 0x6000025501c0>{number = 1, name = main}
 */

class DispatchWorkItem2 {
    private let queue = Queues.get(.serialCustom("DispatchWorkItem2"))()
    
    func create() {
        queue.async {
            sleep(1)
            print("Task 1")
            print(Thread.current)
        }
        queue.async {
            sleep(1)
            print("Task 2")
            print(Thread.current)
        }
        
        let workItem = DispatchWorkItem {
            print("Started Work Item")
            print(Thread.current)
        }
        
        queue.async(execute: workItem)
        
        workItem.cancel() // Не работает если задача уже выполяется
    }
}

//let dispatchWorkItem2 = DispatchWorkItem2()
//dispatchWorkItem2.create()

let imageURL = URL(string: "https://www.planetware.com/photos-large/USNY/usa-best-places-new-york.jpg")!
let view = UIView(frame: CGRect(x: 0, y: 0, width: 300, height: 150))
let imageView = UIImageView(frame: CGRect(x: 0, y: 0, width: 300, height: 150))
imageView.backgroundColor = UIColor.yellow
imageView.contentMode = .scaleAspectFit
view.addSubview(imageView)

//PlaygroundPage.current.liveView = view

func fetchImage() {
    let queue = Queues.get(.utility)()
    queue.async {
        if let data = try? Data(contentsOf: imageURL) {
            Queues.get(.main)().async {
                imageView.image = UIImage(data: data)
            }
        }
    }
}

//fetchImage()

// Dispatch work item image download

func fetchImage2() {
    var data: Data?
    let queue = Queues.get(.userInitiated)()
    let workItem = DispatchWorkItem(qos: .userInteractive) {
        data = try? Data(contentsOf: imageURL)
    }
    
    queue.async(execute: workItem)
    
    workItem.notify(queue: .main) {
        if let imageData = data {
            imageView.image = UIImage(data: imageData)
        }
    }
    
}

//fetchImage2()

// MARK: - URLSession

func fetchImage3() {
    let task = URLSession.shared.dataTask(with: imageURL) { data, response, error in
        if let imageData = data {
            Queues.get(.main)().async {
                imageView.image = UIImage(data: imageData)
                print("Image loaded")
            }
        }
    }
    task.resume()
}

//fetchImage3()

// MARK: - GCD Semaphores

let queue = Queues.get(.cuncurentCustom("GCD Semaphores"))()
let semaphore = DispatchSemaphore(value: 2) // 2    queues are allowed

queue.async {
    semaphore.wait() // -1
    sleep(3)
    print("Task 1")
    semaphore.signal() // +1
}

queue.async {
    semaphore.wait() // -1
    sleep(3)
    print("Task 2")
    semaphore.signal() // +1
}

queue.async {
    semaphore.wait() // -1
    sleep(3)
    print("Task 3")
    semaphore.signal() // +1
}

let sem = DispatchSemaphore(value: 2)

DispatchQueue.concurrentPerform(iterations: 10) { counter in
    sem.wait(timeout: DispatchTime.distantFuture)
    sleep(1)
    print("Block: ", String(counter))
    sem.signal()
}

class SemaphoreTest {
    private let semaphore = DispatchSemaphore(value: 2) // 2    queues are allowed
    private var array = [Int]()
    
    private func methodWork(_ id: Int) {
        semaphore.wait() // -1
        array.append(id)
        print("test array", array.count)
        Thread.sleep(forTimeInterval: 2)
        semaphore.signal()
    }
    
    public func startAllThreads() {
        Queues.get(.systemGlobal)().async {
            self.methodWork(111)
        }
        
        Queues.get(.systemGlobal)().async {
            self.methodWork(122)
        }
        
        Queues.get(.systemGlobal)().async {
            self.methodWork(133)
        }
        
        Queues.get(.systemGlobal)().async {
            self.methodWork(144)
        }
        
        Queues.get(.systemGlobal)().async {
            self.methodWork(155)
        }
        
        Queues.get(.systemGlobal)().async {
            self.methodWork(157)
        }
    }
}

let semaphoreTest = SemaphoreTest()
semaphoreTest.startAllThreads()

