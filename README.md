A simple CLI tool to create and run Linux virtual machines on Mac.

## Creating Virtual Machines

```bash
LinuxVM create <path to JSON configuration>
```

Example JSON configuration

```json
{
    "name": "ubuntu-64",
    "dir": "/Users/test/VMs/",
    "diskSize": 64,
    "cpuCount": 4,
    "memorySize": 8,
    "installerISO": "/Users/test/ubuntu-22.04.2-live-server-arm64.iso"
}
```

## Running Virtual Machines

```bash
LinuxVM run <path to VM directory>
```
