VMDK migration (failover):
.\reattaching-vmdk-v2.ps1 -source VM-PROD01 -target VM-DR01 -csvPath .\reattaching-vmdk-configuration.csv

VMDK migration (failback)
.\reattaching-vmdk-v2.ps1 -source VM-DR01 -target VM-PROD01 -csvPath .\reattaching-vmdk-configuration-cleaning.csv

VMDK generation for test VM:
# Create 15 x 1 GB disks on VM-PROD01 with random controller placement
.\create-test-disks.ps1 -vmName VM-PROD01 -datastore "DatastoreNFS01 - 192.168.1.6"
# Custom count/size and explicit CSV path
.\create-test-disks.ps1 -vmName VM-PROD01 -datastore DatastoreNFS01 -diskCount 15 -diskSizeGB 2 -outputCsvPath .\test-migration.csv
# Then migrate all of them to VM-DR01
.\reattaching-vmdk-v2.ps1 -source VM-PROD01 -target VM-DR01 -csvPath .\reattaching-vmdk-configuration.csv


## VALIDATION Usage:
# Default (VM-PROD01 vs VM-DR01 with local CSV)
.\cmd-validation.ps1
# Custom VMs or CSV
.\cmd-validation.ps1 -vmA VM-PROD01 -vmB VM-DR01 -csvPath .\reattaching-vmdk-configuration.csv
.\cmd-validation.ps1 -vmA VM-PROD01 -csvPath .\reattaching-vmdk-configuration.csv



## Input generation for reattaching script
# Generate CSV from VM-PROD01 (boot disk excluded by default)
.\export-vm-disk-config.ps1 -vmName VM-PROD01
# Custom output path
.\export-vm-disk-config.ps1 -vmName VM-PROD01 -outputCsvPath \reattaching-vmdk-configuration_test.csv
# Include ALL disks including boot disk
.\export-vm-disk-config.ps1 -vmName VM-PROD01 -excludeBootDisk $false