import Foundation
import Virtualization

let createCmdName = "create"

let shouldCreate = CommandLine.argc > 1 && CommandLine.arguments[1] == createCmdName

// User-provided configuration
let vmName = "UbuntuServer"
let baseDir = "/Users/markopapic/VMs/"
let diskSizeGB = UInt64(64)
let cpuCount = 4
let memorySizeGB = UInt64(8)
let installerISOPath = URL(fileURLWithPath: "/Users/markopapic/Downloads/ubuntu-22.04.2-live-server-arm64.iso")

let vmDir = baseDir + vmName + "/"
let mainDiskImagePath = vmDir + "Disk.img"
let machineIDPath = vmDir + "MachineIdentifier"
let memorySize = memorySizeGB  * 1024 * 1024 * 1024
let efiVariableStorePath = vmDir + "NVRAM"

// MARK: Create the Virtual Machine

let vm = createVM()

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

func createVM() -> VZVirtualMachine {
    validateCPUCount()
    validateMemorySize()
    
    let platform = VZGenericPlatformConfiguration()
    let bootLoader = VZEFIBootLoader()
    let disksArray = NSMutableArray()
    
    if shouldCreate {
        print("Creating virtual machine...")
        createVMDir()
        createMainDiskImage()
        platform.machineIdentifier = createMachineID()
        bootLoader.variableStore = createBootloaderStore()
        disksArray.add(createBootableIsoUsbConfiguration())
    } else {
        platform.machineIdentifier = getMachineID()
        bootLoader.variableStore = getBootloaderStore()
    }
    
    let vmConfig = VZVirtualMachineConfiguration()
    
    vmConfig.cpuCount = cpuCount
    vmConfig.memorySize = memorySize
    vmConfig.platform = platform
    vmConfig.bootLoader = bootLoader

    disksArray.add(createBlockDeviceConfiguration())
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

func createVMDir() {
    do {
        try FileManager.default.createDirectory(atPath: vmDir, withIntermediateDirectories: false)
    } catch {
        fatalError("Failed to create “GUI Linux VM.bundle.”")
    }
}

// Create an empty disk image for the virtual machine
func createMainDiskImage() {
    let diskCreated = FileManager.default.createFile(atPath: mainDiskImagePath, contents: nil, attributes: nil)
    if !diskCreated {
        fatalError("Failed to create the main disk image.")
    }

    guard let mainDiskFileHandle = try? FileHandle(forWritingTo: URL(fileURLWithPath: mainDiskImagePath)) else {
        fatalError("Failed to get the file handle for the main disk image.")
    }

    do {
        try mainDiskFileHandle.truncate(atOffset: diskSizeGB * 1024 * 1024 * 1024)
    } catch {
        fatalError("Failed to truncate the main disk image.")
    }
}

func createBlockDeviceConfiguration() -> VZVirtioBlockDeviceConfiguration {
    guard let mainDiskAttachment = try? VZDiskImageStorageDeviceAttachment(url: URL(fileURLWithPath: mainDiskImagePath), readOnly: false) else {
        fatalError("Failed to create main disk attachment.")
    }

    let mainDisk = VZVirtioBlockDeviceConfiguration(attachment: mainDiskAttachment)
    return mainDisk
}

func validateCPUCount() {
    let availableCPUs = ProcessInfo.processInfo.processorCount
    
    if cpuCount > availableCPUs {
        fatalError("Only CPU count is \(availableCPUs).")
    }
}

func validateMemorySize() {
    if memorySize < VZVirtualMachineConfiguration.minimumAllowedMemorySize || memorySize > VZVirtualMachineConfiguration.maximumAllowedMemorySize {
        fatalError("Memory size should be between \(VZVirtualMachineConfiguration.minimumAllowedMemorySize) and \(VZVirtualMachineConfiguration.maximumAllowedMemorySize).")
    }
}

func createMachineID() -> VZGenericMachineIdentifier {
    let machineID = VZGenericMachineIdentifier()
    try! machineID.dataRepresentation.write(to: URL(fileURLWithPath: machineIDPath))
    
    return machineID
}

func getMachineID() -> VZGenericMachineIdentifier {
    guard let machineIDData = try? Data(contentsOf: URL(fileURLWithPath: machineIDPath)) else {
        fatalError("Failed to read the machine identifier.")
    }

    guard let machineId = VZGenericMachineIdentifier(dataRepresentation: machineIDData) else {
        fatalError("Failed to create the machine identifier.")
    }

    return machineId
}

func createBootableIsoUsbConfiguration() -> VZUSBMassStorageDeviceConfiguration {
    guard let intallerDiskAttachment = try? VZDiskImageStorageDeviceAttachment(url: installerISOPath, readOnly: true) else {
        fatalError("Failed to create installer's disk attachment.")
    }

    return VZUSBMassStorageDeviceConfiguration(attachment: intallerDiskAttachment)
}

func createBootloaderStore() -> VZEFIVariableStore {
    guard let efiVariableStore = try? VZEFIVariableStore(creatingVariableStoreAt: URL(fileURLWithPath: efiVariableStorePath)) else {
        fatalError("Failed to create the EFI variable store.")
    }

    return efiVariableStore
}

 func getBootloaderStore() -> VZEFIVariableStore {
    if !FileManager.default.fileExists(atPath: efiVariableStorePath) {
        fatalError("Failed to read the EFI variable store.")
    }

    return VZEFIVariableStore(url: URL(fileURLWithPath: efiVariableStorePath))
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

func printUsageAndExit() -> Never {
    print("Usage: \(CommandLine.arguments[0]) <kernel-path> <initial-ramdisk-path>")
    exit(EX_USAGE)
}
