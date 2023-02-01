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
