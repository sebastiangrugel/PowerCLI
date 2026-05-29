# PowerCLI Scripts

VMware PowerCLI automation scripts for vSphere / vCenter environments.

## Prerequisites

- VMware PowerCLI module installed (`Install-Module VMware.PowerCLI`)
- Active vCenter connection:
  ```powershell
  Set-PowerCLIConfiguration -InvalidCertificateAction Ignore -Confirm:$false
  Connect-VIServer -Server <vcenter> -User administrator@vsphere.local -Password <pass>
  ```

---

## VMDK Reattachment (`VMDK-reattachment\`)

Non-destructive VMDK migration between VMs — designed for planned failover / failback between a production VM and a DR VM.

| Script | Purpose |
|---|---|
| `reattaching-vmdk-v2.ps1` | Detach disks from source VM and reattach to target VM per CSV mapping |
| `cmd-validation.ps1` | Visual `[OK]` / `[!!]` / `[??]` pass/fail comparison of SCSI layout vs CSV |
| `export-vm-disk-config.ps1` | Generate a migration-ready CSV from a VM's current disk layout |
| `create-test-disks.ps1` | Create test disks at random SCSI positions and emit a matching CSV |

### Quick start

```powershell
# Failover: PROD -> DR
.\VMDK-reattachment\reattaching-vmdk-v2.ps1 -source VM-PROD01 -target VM-DR01 -csvPath .\VMDK-reattachment\reattaching-vmdk-configuration.csv

# Failback: DR -> PROD
.\VMDK-reattachment\reattaching-vmdk-v2.ps1 -source VM-DR01 -target VM-PROD01 -csvPath .\VMDK-reattachment\reattaching-vmdk-configuration.csv
```

CSV format — `ControllerKey = 1000 + BusNumber`; unit 7 is reserved on every controller:

```
Source VM vSphere Controller,Source VM vSphere UNIT,Target VM vSphere Controller,Target VM vSphere UNIT
0,1,0,1
1,0,1,0
```

---

## ESXi / Host Management

| Script | Purpose |
|---|---|
| `ESXi-initial-configuration.ps1` | Initial ESXi setup: NTP, syslog target, VMkernel adapters |
| `PowerCli_ESXi_configuration_backup_for_many_hosts.ps1` | Export configuration backup for a list of ESXi hosts |
| `Execute script remotely on ESXi hosts.ps1` | Run a shell script remotely across a list of ESXi hosts |
| `WBEM SERVICE disable in cluster.ps1` | Disable the WBEM service on every host in a named cluster |

---

## HCX (Hybrid Cloud Extension)

| Script | Purpose |
|---|---|
| `HCX-Operations.ps1` | Ad-hoc HCX query snippets: migration status, network extensions, replications |
| `HCX_GetHCXMigrations - continous monitoring.ps1` | Continuous loop showing parked / in-progress / errored / migrated VM states |
| `HCX_Get servers with unsuporrted SCSI controller mode.ps1` | List VMs with SCSI controller types unsupported by HCX |
| `HCX_Get servers with unsuporrted hcx size.ps1` | List VMs whose disk sizes exceed HCX migration limits |

---

## Networking

| Script | Purpose |
|---|---|
| `PowerCli_MigrateVMK2fromVDStoSS.ps1` | Migrate a VMkernel adapter from a VDS to a standard switch |
| `MigrateVMK2fromVDStoSSandMore_v1.ps1` | Extended version: also creates portgroups, migrates pNICs, removes host from VDS |

---

## VM Operations

| Script | Purpose |
|---|---|
| `PowerCLI_Restart_VMGuest.ps1` | Bulk graceful guest restart from a text-file VM list |
| `PowerCli_Creating_VMs_and_vMotionTest_1.0.ps1` | Create N VMs in a cluster and run vMotion round-trip tests |
| `Get GW from VM and more by VMwareTools.ps1` | Extract IP, gateway, subnet, DNS info via VMware Tools |
| `vcenter_check_freespace_inside_OS.ps1` | Report in-guest filesystem free space for a VM |
| `vcd_VM_from_vCD_in_vSphere.ps1` | Correlate a vCloud Director VM name to its vCenter object |
