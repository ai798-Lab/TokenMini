import Foundation
import IOKit

// MARK: - AppleSMC 内核数据结构

/// IOConnectCallStructMethod 的 selector 与 data8 子命令。
/// 只实现读路径:readKeyInfo(拿类型/长度) → readBytes(拿数据);readIndex 用于枚举全部 key。
enum SMCSelector: UInt8 {
    case kernelIndex = 2   // kSMCHandleYPCEvent,IOConnectCallStructMethod 的 selector
    case readBytes   = 5
    case readIndex   = 8
    case readKeyInfo = 9
}

/// 与 AppleSMC 用户客户端交换的参数结构,布局必须严格保持 80 字节,
/// 字段顺序/类型不能动(内核按偏移量读写)。
struct SMCKeyData_t {
    typealias SMCBytes_t = (UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8,
                            UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8,
                            UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8,
                            UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8)

    struct vers_t {
        var major: CUnsignedChar = 0
        var minor: CUnsignedChar = 0
        var build: CUnsignedChar = 0
        var reserved: CUnsignedChar = 0
        var release: CUnsignedShort = 0
    }
    struct LimitData_t {
        var version: UInt16 = 0
        var length: UInt16 = 0
        var cpuPLimit: UInt32 = 0
        var gpuPLimit: UInt32 = 0
        var memPLimit: UInt32 = 0
    }
    struct keyInfo_t {
        var dataSize: IOByteCount32 = 0
        var dataType: UInt32 = 0
        var dataAttributes: UInt8 = 0
    }

    var key: UInt32 = 0
    var vers = vers_t()
    var pLimitData = LimitData_t()
    var keyInfo = keyInfo_t()
    var padding: UInt16 = 0
    var result: UInt8 = 0
    var status: UInt8 = 0
    var data8: UInt8 = 0
    var data32: UInt32 = 0
    var bytes: SMCBytes_t = (0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
                             0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0)
}

/// 读取结果的 Swift 侧容器
struct SMCVal_t {
    var key: String
    var dataSize: UInt32 = 0
    var dataType: String = ""
    var bytes: [UInt8] = Array(repeating: 0, count: 32)
    init(_ key: String) { self.key = key }
}

extension FourCharCode {
    /// 4 个 ASCII 字节的 key 才合法。枚举得到的 key 是内核给的任意字节(可能含 \r\n 或 ≥0x80),
    /// 所以必须可失败:用 precondition 会让一个怪 key 把整个 app 崩掉;
    /// 非 ASCII 字节在 utf8 里占 2 字节,按字节移位会算出另一个 key,读到别的传感器。
    init?(fromString str: String) {
        let bytes = Array(str.utf8)
        guard bytes.count == 4, bytes.allSatisfy({ $0 < 0x80 }) else { return nil }
        self = bytes.reduce(0) { $0 << 8 | UInt32($1) }
    }
    func toString() -> String {
        String(UnicodeScalar(UInt8(self >> 24 & 0xff))) +
        String(UnicodeScalar(UInt8(self >> 16 & 0xff))) +
        String(UnicodeScalar(UInt8(self >> 8  & 0xff))) +
        String(UnicodeScalar(UInt8(self       & 0xff)))
    }
}

// MARK: - SMC 只读客户端

/// AppleSMC 只读客户端。普通用户可打开,非沙盒无需任何 entitlement。
/// 连接开销大,应创建一次全程复用;deinit 里关闭连接。
final class SMC {
    private var conn: io_connect_t = 0

    init?() {
        let service = IOServiceGetMatchingService(kIOMainPortDefault, IOServiceMatching("AppleSMC"))
        guard service != 0 else { return nil }
        let result = IOServiceOpen(service, mach_task_self_, 0, &conn)
        IOObjectRelease(service)
        guard result == kIOReturnSuccess else { return nil }
    }

    deinit { IOServiceClose(conn) }

    /// 读取一个 key,按数据类型解码为 Double。
    /// 字节序是最大的坑:整数(ui8/ui16/ui32)与定点(sp78/fpe2)是大端,
    /// 而 "flt " 是小端 IEEE754 float32 —— Apple Silicon 上风扇/温度全是 flt。
    func getValue(_ key: String) -> Double? {
        var val = SMCVal_t(key)
        guard read(&val) == kIOReturnSuccess, val.dataSize > 0 else { return nil }

        switch val.dataType {
        case "flt ":
            // [UInt8] 的首地址不保证 4 字节对齐,不能直接 load(as: Float32.self)。
            let bits = UInt32(val.bytes[0]) | UInt32(val.bytes[1]) << 8
                | UInt32(val.bytes[2]) << 16 | UInt32(val.bytes[3]) << 24
            let value = Double(Float(bitPattern: bits))
            return value.isFinite ? value : nil
        case "ui8 ":
            return Double(val.bytes[0])
        case "ui16":
            return Double(UInt16(val.bytes[0]) << 8 | UInt16(val.bytes[1]))          // 大端
        case "ui32":
            return Double(UInt32(val.bytes[0]) << 24 | UInt32(val.bytes[1]) << 16 |
                          UInt32(val.bytes[2]) << 8  | UInt32(val.bytes[3]))         // 大端
        case "sp78":
            return Double(Int(Int8(bitPattern: val.bytes[0])) * 256 + Int(val.bytes[1])) / 256.0  // Intel 温度
        case "fpe2":
            return Double((Int(val.bytes[0]) << 6) + (Int(val.bytes[1]) >> 2))       // Intel 风扇转速
        default:
            return nil
        }
    }

    /// 读取字符串型 key(如风扇名 F0ID,类型 {fds,名字在第 4~15 字节)。
    /// 注意 MacBook 上 F%dID 通常不存在,调用方要准备回退名。
    func getStringValue(_ key: String) -> String? {
        var val = SMCVal_t(key)
        guard read(&val) == kIOReturnSuccess, val.dataSize > 0, val.dataType == "{fds" else { return nil }
        let chars = val.bytes[4..<16].filter { $0 != 0 }
        return String(bytes: chars, encoding: .ascii)?.trimmingCharacters(in: .whitespaces)
    }

    /// 枚举 SMC 全部 key(M5 Pro 上 #KEY=3500,只应在启动时调一次并缓存结果)
    func getAllKeys() -> [String] {
        guard let rawCount = getValue("#KEY"), rawCount.isFinite,
              rawCount >= 0, rawCount <= 20_000 else { return [] }
        let count = Int(rawCount)
        var list: [String] = []
        list.reserveCapacity(count)
        for i in 0..<count {
            var input = SMCKeyData_t()
            var output = SMCKeyData_t()
            input.data8 = SMCSelector.readIndex.rawValue
            input.data32 = UInt32(i)
            guard call(&input, &output) == kIOReturnSuccess else { continue }
            list.append(output.key.toString())
        }
        return list
    }

    // MARK: 内部实现

    /// 两步读:先 readKeyInfo 拿类型/长度,再 readBytes 拿数据。
    /// output.result==132 表示 key 不存在(kIOReturnSuccess 但 SMC 层报错)。
    private func read(_ value: inout SMCVal_t) -> kern_return_t {
        var input = SMCKeyData_t()
        var output = SMCKeyData_t()

        guard let code = FourCharCode(fromString: value.key) else { return kIOReturnBadArgument }
        input.key = code
        input.data8 = SMCSelector.readKeyInfo.rawValue
        var result = call(&input, &output)
        guard result == kIOReturnSuccess, output.result == 0 else {
            return result == kIOReturnSuccess ? kIOReturnNotFound : result
        }

        value.dataSize = UInt32(output.keyInfo.dataSize)
        guard value.dataSize > 0, value.dataSize <= UInt32(value.bytes.count) else {
            return kIOReturnBadArgument
        }
        value.dataType = output.keyInfo.dataType.toString()

        input.keyInfo.dataSize = output.keyInfo.dataSize
        input.data8 = SMCSelector.readBytes.rawValue
        result = call(&input, &output)
        guard result == kIOReturnSuccess, output.result == 0 else {
            return result == kIOReturnSuccess ? kIOReturnError : result
        }

        withUnsafeBytes(of: output.bytes) { src in
            let n = min(Int(value.dataSize), value.bytes.count)
            for i in 0..<n { value.bytes[i] = src[i] }
        }
        return kIOReturnSuccess
    }

    private func call(_ input: inout SMCKeyData_t, _ output: inout SMCKeyData_t) -> kern_return_t {
        let inputSize = MemoryLayout<SMCKeyData_t>.stride
        var outputSize = MemoryLayout<SMCKeyData_t>.stride
        return IOConnectCallStructMethod(conn, UInt32(SMCSelector.kernelIndex.rawValue),
                                         &input, inputSize, &output, &outputSize)
    }
}
