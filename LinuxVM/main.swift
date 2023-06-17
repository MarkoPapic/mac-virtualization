import Foundation
import Virtualization

let createCmdName = "create"
let runCmdName = "run"
let userConfigFileName = "UserConfig.json"

guard CommandLine.argc == 3 else {
    fatalError("Invalid arguments.")
}

let command = CommandLine.arguments[1]
let userConfigJson = readUserConfig()
let userConfig = UserConfig(fromJson: userConfigJson)

// MARK: Create the Virtual Machine

// Save user config to be used for subsequent runs
if command == createCmdName {
    createVMDir(path: userConfig.vmDir)
    FileManager.default.createFile(atPath: userConfig.vmDir + userConfigFileName, contents: userConfigJson.data(using: .utf8)!, attributes: nil)
}

let vm = createVM(userConfig: userConfig, shouldCreate: command == createCmdName)

let delegate = Delegate()
vm.delegate = delegate

vm.start { (result) in
    switch result {
    case let .failure(error):
        fatalError("Virtual machine failed to start with error: \(error)")
    default:
        print("Virtual machine successfully started.")
        print("Loading guest OS...")
    }
}

RunLoop.main.run(until: Date.distantFuture)

// MARK: - Virtual Machine Delegate

class Delegate: NSObject {
}

extension Delegate: VZVirtualMachineDelegate {
    func guestDidStop(_ virtualMachine: VZVirtualMachine) {
        print("The guest shut down. Exiting.")
        exit(EXIT_SUCCESS)
    }
}

// MARK: - Helper Functions

func createVM(userConfig: UserConfig, shouldCreate: Bool) -> VZVirtualMachine {
    let platform = VZGenericPlatformConfiguration()
    let bootLoader = VZEFIBootLoader()
    let disksArray = NSMutableArray()
    
    if shouldCreate {
        print("Creating virtual machine...")
        createMainDiskImage(path: userConfig.mainDiskImagePath, size: userConfig.diskSize)
        platform.machineIdentifier = createMachineID(path: userConfig.machineIDPath)
        bootLoader.variableStore = createBootloaderStore(path: userConfig.efiVariableStorePath)
        disksArray.add(createBootableIsoUsbConfiguration(installerISOPath: userConfig.installerISOPath))
    } else {
        platform.machineIdentifier = getMachineID(path: userConfig.machineIDPath)
        bootLoader.variableStore = getBootloaderStore(path: userConfig.efiVariableStorePath)
    }
    
    let vmConfig = VZVirtualMachineConfiguration()
    
    vmConfig.cpuCount = userConfig.cpuCount
    vmConfig.memorySize = userConfig.memorySize
    vmConfig.platform = platform
    vmConfig.bootLoader = bootLoader

    disksArray.add(createBlockDeviceConfiguration(path: userConfig.mainDiskImagePath))
    guard let disks = disksArray as? [VZStorageDeviceConfiguration] else {
        fatalError("Invalid disksArray.")
    }
    vmConfig.storageDevices = disks
    
    vmConfig.networkDevices = [createNetworkDeviceConfiguration()]
    vmConfig.serialPorts = [createConsoleConfiguration()]
    
    try! vmConfig.validate()
    
    let vm = VZVirtualMachine(configuration: vmConfig)
    
    return vm
}

func createVMDir(path: String) {
    do {
        try FileManager.default.createDirectory(atPath: path, withIntermediateDirectories: false)
    } catch {
        fatalError("Failed to create “GUI Linux VM.bundle.”")
    }
}

// Create an empty disk image for the virtual machine
func createMainDiskImage(path: String, size: UInt64) {
    let diskCreated = FileManager.default.createFile(atPath: path, contents: nil, attributes: nil)
    if !diskCreated {
        fatalError("Failed to create the main disk image.")
    }

    guard let mainDiskFileHandle = try? FileHandle(forWritingTo: URL(fileURLWithPath: path)) else {
        fatalError("Failed to get the file handle for the main disk image.")
    }

    do {
        try mainDiskFileHandle.truncate(atOffset: size)
    } catch {
        fatalError("Failed to truncate the main disk image.")
    }
}

func createBlockDeviceConfiguration(path: String) -> VZVirtioBlockDeviceConfiguration {
    guard let mainDiskAttachment = try? VZDiskImageStorageDeviceAttachment(url: URL(fileURLWithPath: path), readOnly: false) else {
        fatalError("Failed to create main disk attachment.")
    }

    let mainDisk = VZVirtioBlockDeviceConfiguration(attachment: mainDiskAttachment)
    return mainDisk
}

func createMachineID(path: URL) -> VZGenericMachineIdentifier {
    let machineID = VZGenericMachineIdentifier()
    try! machineID.dataRepresentation.write(to: path)
    
    return machineID
}

func getMachineID(path: URL) -> VZGenericMachineIdentifier {
    guard let machineIDData = try? Data(contentsOf: path) else {
        fatalError("Failed to read the machine identifier.")
    }

    guard let machineId = VZGenericMachineIdentifier(dataRepresentation: machineIDData) else {
        fatalError("Failed to create the machine identifier.")
    }

    return machineId
}

func createBootableIsoUsbConfiguration(installerISOPath: URL) -> VZUSBMassStorageDeviceConfiguration {
    guard let intallerDiskAttachment = try? VZDiskImageStorageDeviceAttachment(url: installerISOPath, readOnly: true) else {
        fatalError("Failed to create installer's disk attachment.")
    }

    return VZUSBMassStorageDeviceConfiguration(attachment: intallerDiskAttachment)
}

func createBootloaderStore(path: String) -> VZEFIVariableStore {
    guard let efiVariableStore = try? VZEFIVariableStore(creatingVariableStoreAt: URL(fileURLWithPath: path)) else {
        fatalError("Failed to create the EFI variable store.")
    }

    return efiVariableStore
}

func getBootloaderStore(path: String) -> VZEFIVariableStore {
    if !FileManager.default.fileExists(atPath: path) {
        fatalError("Failed to read the EFI variable store.")
    }

    return VZEFIVariableStore(url: URL(fileURLWithPath: path))
}

func createNetworkDeviceConfiguration() -> VZVirtioNetworkDeviceConfiguration {
    let networkDevice = VZVirtioNetworkDeviceConfiguration()
    networkDevice.attachment = VZNATNetworkDeviceAttachment()

    return networkDevice
}

/// Creates a serial configuration object for a virtio console device,
/// and attaches it to stdin and stdout.
func createConsoleConfiguration() -> VZSerialPortConfiguration {
    let consoleConfiguration = VZVirtioConsoleDeviceSerialPortConfiguration()

    let inputFileHandle = FileHandle.standardInput
    let outputFileHandle = FileHandle.standardOutput

    // Put stdin into raw mode, disabling local echo, input canonicalization,
    // and CR-NL mapping.
    var attributes = termios()
    tcgetattr(inputFileHandle.fileDescriptor, &attributes)
    attributes.c_iflag &= ~tcflag_t(ICRNL)
    attributes.c_lflag &= ~tcflag_t(ICANON | ECHO)
    tcsetattr(inputFileHandle.fileDescriptor, TCSANOW, &attributes)

    let stdioAttachment = VZFileHandleSerialPortAttachment(fileHandleForReading: inputFileHandle,
                                                           fileHandleForWriting: outputFileHandle)

    consoleConfiguration.attachment = stdioAttachment

    return consoleConfiguration
}

func readUserConfig() -> String {
    let command = CommandLine.arguments[1]

    var userConfigPath : String
    if command == createCmdName {
        userConfigPath = CommandLine.arguments[2] // JSON path
    } else if command == runCmdName {
        userConfigPath = CommandLine.arguments[2] + "/" + userConfigFileName // VM dir path
    } else {
        fatalError("Unrecognized command.")
    }

    let userConfigJson = try! String(contentsOfFile: userConfigPath)
    
    return userConfigJson
}

// MARK: - Data Models

struct UserConfig {
    var vmDir: String
    var mainDiskImagePath: String
    var diskSize: UInt64
    var cpuCount: Int
    var memorySize: UInt64 // multiply
    var installerISOPath: URL
    var machineIDPath: URL
    var efiVariableStorePath: String
    
    init(fromJson json: String) {
        let data = json.data(using: .utf8)!
        let dict = try! JSONSerialization.jsonObject(with: data, options: .allowFragments) as! [String: Any]
        
        
        let vmName = dict["name"] as! String
        let baseDir = dict["dir"] as! String
        vmDir = baseDir + vmName + "/"
        
        mainDiskImagePath = vmDir + "Disk.img"
        
        let diskSizeGB = dict["diskSize"] as! UInt64
        diskSize = diskSizeGB * 1024 * 1024 * 1024
        
        let desiredCpuCount = dict["cpuCount"] as! Int
        let availableCPUs = ProcessInfo.processInfo.processorCount
        if desiredCpuCount > availableCPUs {
            fatalError("Max CPU count is \(availableCPUs).")
        }
        cpuCount = desiredCpuCount
        
        let desiredMemorySizeGB = dict["memorySize"] as! UInt64
        let desiredMemorySize = desiredMemorySizeGB  * 1024 * 1024 * 1024
        if desiredMemorySize < VZVirtualMachineConfiguration.minimumAllowedMemorySize || desiredMemorySize > VZVirtualMachineConfiguration.maximumAllowedMemorySize {
            fatalError("Memory size should be between \(VZVirtualMachineConfiguration.minimumAllowedMemorySize) and \(VZVirtualMachineConfiguration.maximumAllowedMemorySize).")
        }
        memorySize = desiredMemorySize
        
        installerISOPath = URL(fileURLWithPath: dict["installerISO"] as! String)
        machineIDPath = URL(fileURLWithPath: vmDir + "MachineIdentifier")
        efiVariableStorePath = vmDir + "NVRAM"
    }
}
