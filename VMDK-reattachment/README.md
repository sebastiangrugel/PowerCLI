# VMDK Reattachment Scripts

PowerShell scripts for non-destructively migrating VMDK disks between VMware VMs using PowerCLI. Supports planned failover, failback, and test-lab disk creation.

---

## Prerequisites

| Requirement | Command |
|-------------|---------|
| VMware PowerCLI module | `Install-Module VMware.PowerCLI` |
| Active vCenter session | See [Connecting to vCenter](#connecting-to-vcenter) |

### Connecting to vCenter

```powershell
# Suppress self-signed certificate warnings (common in lab environments)
Set-PowerCLIConfiguration -InvalidCertificateAction Ignore -Confirm:$false

# Connect
Connect-VIServer -Server vcenter-c.avengers.local -User administrator@vsphere.local -Password <your-password>

# Verify connection
$global:DefaultVIServer

# Disconnect when done
Disconnect-VIServer -Confirm:$false
```

All scripts require an active `$global:DefaultVIServer` session before running.

---

## Scripts Overview

| Script | Purpose |
|--------|---------|
| [`reattaching-vmdk-v2.ps1`](#reattaching-vmdk-v2ps1) | Migrate disks between VMs using a CSV mapping |
| [`cmd-validation.ps1`](#cmd-validationps1) | Validate disk and controller state with visual pass/fail output |
| [`export-vm-disk-config.ps1`](#export-vm-disk-configps1) | Generate a migration CSV from a VM's current disk layout |
| [`create-test-disks.ps1`](#create-test-disksps1) | Create test disks with random SCSI placement and generate a migration CSV |

---

## CSV Configuration Format

The CSV file defines how each disk maps from source VM position to target VM position.

**File:** `reattaching-vmdk-configuration.csv`

```csv
Source VM vSphere Controller,Source VM vSphere UNIT,Target VM vSphere Controller,Target VM vSphere UNIT
0,1,0,1
1,0,1,0
2,13,2,13
```

| Column | Description |
|--------|-------------|
| `Source VM vSphere Controller` | SCSI bus number on the source VM (0–3) |
| `Source VM vSphere UNIT` | SCSI unit number on that bus |
| `Target VM vSphere Controller` | SCSI bus number on the target VM (0–3) |
| `Target VM vSphere UNIT` | SCSI unit number on that bus |

**Internally**, vSphere uses `ControllerKey = 1000 + BusNumber` (e.g. bus 2 → key 1002). Unit 7 is reserved on every controller (SCSI initiator ID).

---

## reattaching-vmdk-v2.ps1

Migrates VMDK disks from one VM to another non-destructively. Disks are detached from the source and re-attached to the target at the positions defined in the CSV.

### Parameters

| Parameter | Required | Description |
|-----------|----------|-------------|
| `-source` | Yes | Name of the source VM (disks move FROM here) |
| `-target` | Yes | Name of the target VM (disks move TO here) |
| `-csvPath` | Yes | Path to the disk mapping CSV |

### Usage

```powershell
# Failover: move disks from production to DR
.\reattaching-vmdk-v2.ps1 -source VM-PROD01 -target VM-DR01 -csvPath .\reattaching-vmdk-configuration.csv

# Failback: return disks from DR to production
.\reattaching-vmdk-v2.ps1 -source VM-DR01 -target VM-PROD01 -csvPath .\reattaching-vmdk-configuration.csv
```

### Execution Flow

```
1. Resolve source and target VMs
2. Display pre-run state (controllers + disks + UUID for both VMs)
3. Display planned CSV mappings
4. Prompt: "Proceed with disk migration? (yes/no)"
           ↓ yes
5. Create any missing SCSI controllers on target
6. For each CSV row:
   a. Locate disk on source by (Controller, Unit)
   b. Detach from source (non-destructive — VMDK file is NOT deleted)
   c. Attach to target at specified (Controller, Unit)
7. Restore any SCSI controllers auto-removed from source by vSphere
8. Display post-run state for both VMs
```

### Logging

Every run writes a timestamped log to the `log\` subfolder next to the script:

```
log\log_20260529_143022.log
```

The log path is printed at the start of each run. The log captures everything visible on screen.

### Example Output

```
Log  : E:\Scripts\VMDK-reattachment\log\log_20260529_143022.log
Resolving VMs...
  Source : VM-PROD01
  Target : VM-DR01

=== Pre-run State ===
  SCSI Controllers on VM-PROD01: ...
  Attached Disks on VM-PROD01: ...
  Planned mappings from CSV: ...

Proceed with disk migration? (yes/no): yes

Required SCSI controllers on target: 0, 1, 2
  SCSI controller BusNumber=1 already present on VM-DR01.
  Creating SCSI controller BusNumber=2 (ParaVirtualSCSIController) on VM-DR01...
    -> Done.

Processing disk mappings...
  [VM-PROD01 SCSI0:1] -> [VM-DR01 SCSI0:1]
    Path : [DatastoreNFS01] VM-PROD01/VM-PROD01_1.vmdk (2 GB)
    Detaching from VM-PROD01...
    Attaching to VM-DR01 at SCSI0:1...
    OK.

Restoring vacated SCSI controllers on source (VM-PROD01)...
  BusNumber=1 was auto-removed — recreating as ParaVirtualSCSIController...
    -> Done.

=== Post-run State ===
...
```

### Important Notes

- Both VMs **must be powered off** before running.
- Disks defined in the CSV must exist at the specified source positions — missing disks are skipped with a warning.
- vSphere automatically removes empty SCSI controllers when their last disk is detached. The script recreates them afterward using the original controller type.
- The first disk on SCSI 0:0 (OS boot disk) should never be included in the CSV — it cannot be detached while the VM exists.

---

## cmd-validation.ps1

Compares the SCSI controller and disk configuration of two VMs against an expected CSV mapping. Outputs a three-section visual report with `[OK]`, `[!!]`, and `[??]` indicators.

### Parameters

| Parameter | Required | Default | Description |
|-----------|----------|---------|-------------|
| `-vmA` | No | `VM-PROD01` | Reference VM (source of truth) |
| `-vmB` | No | `VM-DR01` | VM to validate |
| `-csvPath` | No | `.\reattaching-vmdk-configuration.csv` | Expected disk mapping |

### Usage

```powershell
# Default: validate VM-DR01 against VM-PROD01 using local CSV
.\cmd-validation.ps1

# Custom VMs
.\cmd-validation.ps1 -vmA VM-PROD01 -vmB VM-DR01

# Custom CSV
.\cmd-validation.ps1 -vmA VM-PROD01 -vmB VM-DR01 -csvPath .\my-mapping.csv
```

### Output Sections

#### Section 1 — SCSI Controller Comparison

Compares every SCSI bus number present on either VM.

```
=====  SCSI Controller Comparison  =====
  BUS     VM-PROD01 (Reference)              VM-DR01 (Check)                    Result
  SCSI0   VirtualLsiLogicSASController       VirtualLsiLogicSASController       [OK]
  SCSI1   ParaVirtualSCSIController          ParaVirtualSCSIController          [OK]
  SCSI2   ParaVirtualSCSIController          (missing)                          [!!]
  SCSI3   VirtualLsiLogicSASController       (missing)                          [!!]
  Controllers: 2 passed, 2 failed
```

#### Section 2 — CSV Disk Mapping Validation

For each CSV row, validates three conditions on the check VM:

| Column | Checks |
|--------|--------|
| `Ctrl` | Does the required SCSI controller bus exist on the check VM? |
| `Disk` | Is there a disk at the expected target position? |
| `UUID` | Does the UUID at the target position match the UUID at the source position? |

```
=====  Disk Mapping Validation  =====
  #     Src Pos     Tgt Pos     UUID @ Src (VM-PROD01)    Ctrl    Disk    UUID @ Tgt (VM-DR01)      UUID    Result
  1     SCSI0:1     SCSI0:1     6000C29d-e5de-223b~       [OK]    [OK]    6000C29d-e5de-223b~       [OK]    [OK]
  2     SCSI1:0     SCSI1:0     6000C295-e19a-e4df~       [OK]    [OK]    6000C295-e19a-e4df~       [OK]    [OK]
  3     SCSI2:13    SCSI2:13    6000C297-7841-f11a~       [!!]    [!!]    (no disk at tgt)          [!!]    [!!]
  Disk mappings: 2 passed, 1 failed
```

> **UUID column** shows `[??]` when the source position is already empty — this is normal after a successful migration (the disk left the source VM).

#### Section 3 — UUID Cross-Reference

Lists every disk UUID found across both VMs with its position on each.

```
=====  UUID Cross-Reference  =====
  UUID                                    VM-PROD01 Pos  VM-DR01 Pos   Filename              Location
  6000C296-32ce-bfdf-ae61-9cea6f0f6c64   SCSI0:0        -             VM-PROD01.vmdk        VM-PROD01 only
  6000C29d-e5de-223b-558a-d810baccc697   -              SCSI0:1       VM-PROD01_1.vmdk      VM-DR01 only
  6000C295-e19a-e4df-bf59-f56917997538   -              SCSI1:0       VM-PROD01_2.vmdk      VM-DR01 only
```

A UUID appearing on **both** VMs is flagged `[??] Both VMs` — a VMDK cannot be safely attached to two VMs simultaneously.

### Legend

| Indicator | Meaning |
|-----------|---------|
| `[OK]` (green) | Check passed |
| `[!!]` (red) | Check failed — action required |
| `[??]` (yellow) | Ambiguous — verify manually |

---

## export-vm-disk-config.ps1

Reads a VM's current disk layout and writes a `reattaching-vmdk-v2.ps1`-compatible CSV with source and target positions set to the same values. Use this to build a migration CSV from a VM that already has all its disks attached, rather than writing the CSV by hand.

### Parameters

| Parameter | Required | Default | Description |
|-----------|----------|---------|-------------|
| `-vmName` | Yes | — | VM to read disk layout from |
| `-outputCsvPath` | No | `.\reattaching-vmdk-configuration.csv` | Path to write the generated CSV |
| `-excludeBootDisk` | No | `$true` | Exclude SCSI 0:0 (OS boot disk) from output |

### Usage

```powershell
# Generate CSV from VM-PROD01 (boot disk excluded by default)
.\export-vm-disk-config.ps1 -vmName VM-PROD01

# Custom output path
.\export-vm-disk-config.ps1 -vmName VM-PROD01 -outputCsvPath .\prod-layout.csv

# Include all disks including boot disk
.\export-vm-disk-config.ps1 -vmName VM-PROD01 -excludeBootDisk $false
```

### Output

The script prints a full disk inventory table with an `Include` / `SKIP (boot)` column before writing, so you can verify the export before using it:

```
VM        : VM-PROD01  |  Power: PoweredOff
Output    : .\reattaching-vmdk-configuration.csv
Boot disk : excluded (SCSI0:0)

  Disk inventory on VM-PROD01:
Name         CapacityGB  SCSI Bus  Unit  Include      UUID                                  Filename
Hard disk 1        0.00         0     0  SKIP (boot)  6000C296-32ce-bfdf-ae61-9cea6f0f6c64  ...
Hard disk 2        2.00         0     1  YES          6000C29d-e5de-223b-558a-d810baccc697  ...
...

  Exported : 18 disk(s)
  Skipped  : 1 disk(s) (boot disk excluded)
  CSV path : E:\Scripts\VMDK-reattachment\reattaching-vmdk-configuration.csv

  Use with:
    .\reattaching-vmdk-v2.ps1 -source VM-PROD01 -target <targetVM> -csvPath "..."
```

### Notes

- The generated CSV maps every disk as `source = target` (same controller:unit). Edit the Target columns manually if you need disks to land at different positions on the destination VM.
- Passing `\filename.csv` (leading backslash, no drive letter) is handled correctly — the script resolves it relative to the current working directory rather than the drive root.

---

## create-test-disks.ps1

Creates a specified number of new VMDK disks on a VM, placing each on a randomly selected existing SCSI controller. Generates a `reattaching-vmdk-v2.ps1`-compatible CSV for subsequent migration testing.

### Parameters

| Parameter | Required | Default | Description |
|-----------|----------|---------|-------------|
| `-vmName` | Yes | — | VM to create disks on |
| `-datastore` | Yes | — | Datastore name where VMDK files are created |
| `-diskCount` | No | `15` | Number of disks to create |
| `-diskSizeGB` | No | `1` | Size per disk in GB |
| `-outputCsvPath` | No | `.\reattaching-vmdk-configuration.csv` | Path to write the generated CSV |

### Usage

```powershell
# Create 15 x 1 GB disks on VM-PROD01 with random SCSI placement
.\create-test-disks.ps1 -vmName VM-PROD01 -datastore DatastoreNFS01

# Custom count and size
.\create-test-disks.ps1 -vmName VM-PROD01 -datastore DatastoreNFS01 -diskCount 10 -diskSizeGB 2

# Write CSV to a custom path
.\create-test-disks.ps1 -vmName VM-PROD01 -datastore DatastoreNFS01 -outputCsvPath .\test-migration.csv
```

### Output

The script prints a summary table after completion and writes the CSV:

```
VM        : VM-PROD01
Datastore : DatastoreNFS01
Disks     : 15 x 1 GB

Available SCSI controllers: ...

Creating 15 disks with random controller assignment...
  Disk 1  ->  SCSI2:3
    Created: SCSI2:3  |  [DatastoreNFS01] VM-PROD01/VM-PROD01_disk1_scsi2u3.vmdk
  Disk 2  ->  SCSI0:5
    Created: SCSI0:5  |  [DatastoreNFS01] VM-PROD01/VM-PROD01_disk2_scsi0u5.vmdk
  ...

=== Created Disks ===
...

CSV written to : .\reattaching-vmdk-configuration.csv  (15 rows)
Use with      : .\reattaching-vmdk-v2.ps1 -source VM-PROD01 -target <targetVM> -csvPath .\reattaching-vmdk-configuration.csv
```

### Notes

- Requires the VM to have at least one existing SCSI controller.
- Unit 7 is always excluded from placement (reserved by vSphere as the SCSI initiator).
- Each controller supports up to 15 disks (units 0–15 minus unit 7). With 4 controllers the maximum is 60 disks.
- The generated CSV maps source and target at the same position (`SCSI X:Y → SCSI X:Y`). Edit the CSV manually if you want disks to land at different positions on the target VM.

---

## Typical Workflows

### Workflow 1 — Planned Failover (PROD → DR)

```powershell
# 1. Inspect current state
.\cmd-validation.ps1 -vmA VM-PROD01 -vmB VM-DR01

# 2. Run migration
.\reattaching-vmdk-v2.ps1 -source VM-PROD01 -target VM-DR01 -csvPath .\reattaching-vmdk-configuration.csv

# 3. Validate result
.\cmd-validation.ps1 -vmA VM-PROD01 -vmB VM-DR01
```

### Workflow 2 — Failback (DR → PROD)

```powershell
# Same CSV works in reverse — source and target arguments are swapped
.\reattaching-vmdk-v2.ps1 -source VM-DR01 -target VM-PROD01 -csvPath .\reattaching-vmdk-configuration.csv

.\cmd-validation.ps1 -vmA VM-DR01 -vmB VM-PROD01
```

### Workflow 3 — Generate CSV from Existing VM Layout

```powershell
# Export current disk positions of VM-PROD01 to a migration CSV
.\export-vm-disk-config.ps1 -vmName VM-PROD01

# Review the generated CSV, then run the migration
.\reattaching-vmdk-v2.ps1 -source VM-PROD01 -target VM-DR01 -csvPath .\reattaching-vmdk-configuration.csv
```

### Workflow 4 — Test Lab with Random Disks

```powershell
# Create 15 random test disks on VM-PROD01 and generate a CSV
.\create-test-disks.ps1 -vmName VM-PROD01 -datastore DatastoreNFS01

# Migrate them to VM-DR01
.\reattaching-vmdk-v2.ps1 -source VM-PROD01 -target VM-DR01 -csvPath .\reattaching-vmdk-configuration.csv

# Validate result
.\cmd-validation.ps1

# Migrate back
.\reattaching-vmdk-v2.ps1 -source VM-DR01 -target VM-PROD01 -csvPath .\reattaching-vmdk-configuration.csv
```

---

## Log Files

`reattaching-vmdk-v2.ps1` automatically writes a transcript of every run to:

```
<script directory>\log\log_YYYYMMDD_HHmmss.log
```

Logs capture everything printed to the console — pre/post state tables, per-disk progress, warnings, and errors. The log folder is created automatically on first run.
