# Copyright (c) Microsoft Corporation.
# Licensed under the MIT License.

#
# Validation rules for Azure Virtual Machines
#

#region Virtual machine

# Synopsis: Virtual machines should use managed disks
Rule 'Azure.VM.UseManagedDisks' -Ref 'AZR-000238' -Type 'Microsoft.Compute/virtualMachines' -Tag @{ release = 'GA'; ruleSet = '2020_06'; 'Azure.WAF/pillar' = 'Security'; } -Labels @{ 'Azure.ASB.v3/control' = 'DP-4' } {
    # Check OS disk
    $Assert.
    NullOrEmpty($TargetObject, 'properties.storageProfile.osDisk.vhd.uri').
    WithReason(($LocalizedData.UnmanagedDisk -f $TargetObject.properties.storageProfile.osDisk.name), $True);

    # Check data disks
    foreach ($dataDisk in $TargetObject.properties.storageProfile.dataDisks) {
        $Assert.
        NullOrEmpty($dataDisk, 'vhd.uri').
        WithReason(($LocalizedData.UnmanagedDisk -f $dataDisk.name), $True);
    }
}

# Synopsis: Check disk caching is configured correctly for the workload
Rule 'Azure.VM.DiskCaching' -Ref 'AZR-000242' -Type 'Microsoft.Compute/virtualMachines' -Tag @{ release = 'GA'; ruleSet = '2020_06' } {
    # Check OS disk
    $Assert.HasFieldValue($TargetObject, 'properties.storageProfile.osDisk.caching', 'ReadWrite');

    # Check data disks
    $dataDisks = @($TargetObject.properties.storageProfile.dataDisks | Where-Object {
            $Null -ne $_
        })
    if ($dataDisks.Length -gt 0) {
        foreach ($disk in $dataDisks) {
            if ($disk.managedDisk.storageAccountType -eq 'Premium_LRS') {
                $Assert.HasFieldValue($disk, 'caching', 'ReadOnly');
            }
            else {
                $Assert.HasFieldValue($disk, 'caching', 'None');
            }
        }
    }
}

# Synopsis: Use Hybrid Use Benefit
Rule 'Azure.VM.UseHybridUseBenefit' -Ref 'AZR-000243' -If { SupportsHybridUse } -Tag @{ release = 'GA'; ruleSet = '2020_06' } {
    $Assert.HasFieldValue($TargetObject, 'properties.licenseType', 'Windows_Server');
}

# Synopsis: Use accelerated networking for supported operating systems and VM types.
Rule 'Azure.VM.AcceleratedNetworking' -Ref 'AZR-000244' -If { SupportsAcceleratedNetworking } -Tag @{ release = 'GA'; ruleSet = '2020_06' } {
    $resources = @(GetSubResources -ResourceType 'Microsoft.Network/networkInterfaces');
    if ($resources.Length -eq 0) {
        return $Assert.Pass();
    }
    foreach ($interface in $resources) {
        $Assert.HasFieldValue($interface, 'Properties.enableAcceleratedNetworking', $True);
    }
}

# Synopsis: Linux VMs should use public key pair
Rule 'Azure.VM.PublicKey' -Ref 'AZR-000245' -If { VMHasLinuxOS } -Tag @{ release = 'GA'; ruleSet = '2020_06' } {
    $Assert.HasFieldValue($TargetObject, 'Properties.osProfile.linuxConfiguration.disablePasswordAuthentication', $True)
}

# Synopsis: Ensure that the VM agent is provisioned automatically
Rule 'Azure.VM.Agent' -Ref 'AZR-000246' -Type 'Microsoft.Compute/virtualMachines' -Tag @{ release = 'GA'; ruleSet = '2020_06' } {
    $Assert.HasDefaultValue($TargetObject, 'Properties.osProfile.linuxConfiguration.provisionVMAgent', $True)
    $Assert.HasDefaultValue($TargetObject, 'Properties.osProfile.windowsConfiguration.provisionVMAgent', $True)
}

# Synopsis: Ensure automatic updates are enabled at deployment
Rule 'Azure.VM.Updates' -Ref 'AZR-000247' -Type 'Microsoft.Compute/virtualMachines' -If { IsWindowsOS } -Tag @{ release = 'GA'; ruleSet = '2020_06'; 'Azure.WAF/pillar' = 'Security'; } -Labels @{ 'Azure.ASB.v3/control' = 'ES-3' } {
    $Assert.HasDefaultValue($TargetObject, 'Properties.osProfile.windowsConfiguration.enableAutomaticUpdates', $True)
}

# Synopsis: Use VM naming requirements
Rule 'Azure.VM.Name' -Ref 'AZR-000248' -Type 'Microsoft.Compute/virtualMachines' -Tag @{ release = 'GA'; ruleSet = '2020_06' } {
    # https://docs.microsoft.com/en-us/azure/azure-resource-manager/management/resource-name-rules#microsoftcompute

    # Between 1 and 64 characters long
    $Assert.GreaterOrEqual($TargetObject, 'Name', 1)
    $Assert.LessOrEqual($TargetObject, 'Name', 64)

    # Alphanumerics, underscores, periods, and hyphens
    # Start with alphanumeric
    # End with alphanumeric or underscore
    Match 'Name' '^[A-Za-z0-9]((-|\.)*\w){0,79}$'
}

# Synopsis: Use VM naming requirements
Rule 'Azure.VM.ComputerName' -Ref 'AZR-000249' -Type 'Microsoft.Compute/virtualMachines' -Tag @{ release = 'GA'; ruleSet = '2020_06' } {
    # https://docs.microsoft.com/en-us/azure/azure-resource-manager/management/resource-name-rules#microsoftcompute

    $maxLength = 64
    $matchExpression = '^[A-Za-z0-9]([A-Za-z0-9-.]){0,63}$'
    if (IsWindowsOS) {
        $maxLength = 15

        # Alphanumeric or hyphens
        # Can not include only numbers
        $matchExpression = '^[A-Za-z0-9-]{0,14}[A-Za-z-][A-Za-z0-9-]{0,14}$'
    }

    # Between 1 and 15/ 64 characters long
    $Assert.GreaterOrEqual($TargetObject, 'Properties.osProfile.computerName', 1)
    $Assert.LessOrEqual($TargetObject, 'Properties.osProfile.computerName', $maxLength)

    # Alphanumerics and hyphens
    # Start and end with alphanumeric
    Match 'Properties.osProfile.computerName' $matchExpression
}

#endregion Virtual machine

#region Managed Disks

# Synopsis: Managed disks should be attached to virtual machines
Rule 'Azure.VM.DiskAttached' -Ref 'AZR-000250' -Type 'Microsoft.Compute/disks' -If { ($TargetObject.ResourceName -notlike '*-ASRReplica') -and (IsExport) } -Tag @{ release = 'GA'; ruleSet = '2020_06'; 'Azure.WAF/pillar' = 'Security'; } -Labels @{ 'Azure.ASB.v3/control' = 'DP-4' } {
    # Disks should be attached unless they are used by ASR, which are not attached until fail over
    # Disks for VMs that are off are marked as Reserved
    Within 'properties.diskState' 'Attached', 'Reserved' -Reason $LocalizedData.ResourceNotAssociated
}

# TODO: Check IOPS

# Synopsis: Managed disk is smaller than SKU size
Rule 'Azure.VM.DiskSizeAlignment' -Ref 'AZR-000251' -Type 'Microsoft.Compute/disks' -Tag @{ release = 'GA'; ruleSet = '2020_06' } {
    $diskSize = @(32, 64, 128, 256, 512, 1024, 2048, 4096, 8192, 16384, 32768)
    $actualSize = $TargetObject.Properties.diskSizeGB

    # Find the closest disk size
    $i = 0;
    while ($actualSize -gt $diskSize[$i]) {
        $i++;
    }

    # Actual disk size should be the disk size within 5GB
    $Assert.GreaterOrEqual($TargetObject, 'Properties.diskSizeGB', ($diskSize[$i] - 5));
}

# TODO: Check number of disks

# Synopsis: Use Azure Disk Encryption
Rule 'Azure.VM.ADE' -Ref 'AZR-000252' -Type 'Microsoft.Compute/disks' -If { IsExport } -Tag @{ release = 'GA'; ruleSet = '2020_06'; 'Azure.WAF/pillar' = 'Security'; } -Labels @{ 'Azure.ASB.v3/control' = 'DP-3' } {
    $Assert.HasFieldValue($TargetObject, 'Properties.encryptionSettingsCollection.enabled', $True)
    $Assert.HasFieldValue($TargetObject, 'Properties.encryptionSettingsCollection.encryptionSettings')
}

# Synopsis: Use Managed Disk naming requirements
Rule 'Azure.VM.DiskName' -Ref 'AZR-000253' -Type 'Microsoft.Compute/disks' -Tag @{ release = 'GA'; ruleSet = '2020_06' } {
    # https://docs.microsoft.com/en-us/azure/azure-resource-manager/management/resource-name-rules#microsoftcompute

    # Between 1 and 80 characters long
    $Assert.GreaterOrEqual($TargetObject, 'Name', 1)
    $Assert.LessOrEqual($TargetObject, 'Name', 80)

    # Alphanumerics, underscores, periods, and hyphens
    # Start with alphanumeric
    # End with alphanumeric or underscore
    Match 'Name' '^[A-Za-z0-9]((-|\.)*\w){0,79}$'
}

#endregion Managed Disks

#region Availability set

# Synopsis: Availability sets should be deployed with at least two members
Rule 'Azure.VM.ASMinMembers' -Ref 'AZR-000255' -Type 'Microsoft.Compute/availabilitySets' -If { IsExport } -Tag @{ release = 'GA'; ruleSet = '2020_06' } {
    $Assert.GreaterOrEqual($TargetObject, 'properties.virtualMachines', 2)
}

# Synopsis: Use Availability Set naming requirements
Rule 'Azure.VM.ASName' -Ref 'AZR-000256' -Type 'Microsoft.Compute/availabilitySets' -Tag @{ release = 'GA'; ruleSet = '2020_06' } {
    # https://docs.microsoft.com/en-us/azure/azure-resource-manager/management/resource-name-rules#microsoftcompute

    # Between 1 and 80 characters long
    $Assert.GreaterOrEqual($TargetObject, 'Name', 1)
    $Assert.LessOrEqual($TargetObject, 'Name', 80)

    # Alphanumerics, underscores, periods, and hyphens
    # Start with alphanumeric
    # End with alphanumeric or underscore
    Match 'Name' '^[A-Za-z0-9]((-|\.)*\w){0,79}$'
}

#endregion Availability set

#region Network Interface

# Synopsis: Network interfaces (NICs) should be attached.
Rule 'Azure.VM.NICAttached' -Ref 'AZR-000257' -Type 'Microsoft.Network/networkInterfaces' -If { IsExport } -Tag @{ release = 'GA'; ruleSet = '2020_06' } {
    $Assert.AnyOf(
        $Assert.HasFieldValue($TargetObject, 'Properties.virtualMachine.id'),
        $Assert.HasFieldValue($TargetObject, 'Properties.privateEndpoint.id')
    )
}

# Synopsis: Use NIC naming requirements
Rule 'Azure.VM.NICName' -Ref 'AZR-000259' -Type 'Microsoft.Network/networkInterfaces' -Tag @{ release = 'GA'; ruleSet = '2020_06' } {
    # https://docs.microsoft.com/en-us/azure/azure-resource-manager/management/resource-name-rules#microsoftnetwork

    # Between 1 and 80 characters long
    $Assert.GreaterOrEqual($TargetObject, 'Name', 1)
    $Assert.LessOrEqual($TargetObject, 'Name', 80)

    # Alphanumerics, underscores, periods, and hyphens
    # Start with alphanumeric
    # End with alphanumeric or underscore
    Match 'Name' '^[A-Za-z0-9]((-|\.)*\w){0,79}$'
}

#endregion Network Interface

#region Proximity Placement Groups

# Synopsis: Use Proximity Placement Groups naming requirements
Rule 'Azure.VM.PPGName' -Ref 'AZR-000260' -Type 'Microsoft.Compute/proximityPlacementGroups' -Tag @{ release = 'GA'; ruleSet = '2020_06' } {
    # https://docs.microsoft.com/en-us/azure/azure-resource-manager/management/resource-name-rules#microsoftcompute

    # Between 1 and 80 characters long
    $Assert.GreaterOrEqual($TargetObject, 'Name', 1)
    $Assert.LessOrEqual($TargetObject, 'Name', 80)

    # Alphanumerics, underscores, periods, and hyphens
    # Start and end with alphanumeric
    Match 'Name' '^[A-Za-z0-9]((-|\.|_)*[A-Za-z0-9]){0,79}$'
}

#endregion Proximity Placement Groups

#region Azure Monitor Agent

# Synopsis: Use Azure Monitor Agent as replacement for Log Analytics Agent.
Rule 'Azure.VM.MigrateAMA' -Ref 'AZR-000317' -Type 'Microsoft.Compute/virtualMachines' -If { HasOMSOrAMAExtension } -Tag @{ release = 'GA'; ruleSet = '2022_12' } {
    $extensions = @(GetSubResources -ResourceType 'Microsoft.Compute/virtualMachines/extensions' |
        Where-Object { (($_.Properties.publisher -eq 'Microsoft.EnterpriseCloud.Monitoring') -and ($_.Properties.type -eq 'MicrosoftMonitoringAgent')) -or
            (($_.Properties.publisher -eq 'Microsoft.EnterpriseCloud.Monitoring') -and ($_.Properties.type -eq 'OmsAgentForLinux')) })

    $Assert.Less($extensions, '.', 1).Reason($LocalizedData.LogAnalyticsAgentDeprecated).PathPrefix('resources')
}

#endregion Azure Monitor Agent
