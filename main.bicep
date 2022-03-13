// Deployment parameters
@description('Location to depoloy all resources. Leave this value as-is to inherit the location from the parent resource group.')
param location string = resourceGroup().location

// Virtual network parameters
@description('Name for the virtual network.')
param virtualNetworkName string = 'VNET'

@description('Address space for the virtual network, in IPv4 CIDR notation.')
param virtualNetworkAddressSpace string = '10.0.0.0/16'

@description('Name for the default subnet in the virtual network.')
param subnetName string = 'Subnet'

@description('Address range for the default subnet, in IPv4 CIDR notation.')
param subnetAddressRange string = '10.0.0.0/24'

@description('Public IP address of your local machine, in IPv4 CIDR notation. Used to restrict remote access to resources within the virtual network.')
param allowedSourceIPAddress string = '0.0.0.0/0'

// Virtual machine parameters
@description('Name for the domain controller virtual machine.')
param domainControllerName string = 'DC01'

@description('Name for the workstation virtual machine.')
param workstationName string = 'WS01'

// Domain parameters
@description('FQDN for the Active Directory domain (e.g. contoso.com).')
@minLength(3)
param domainFQDN string = 'contoso.com'

@description('Administrator username for both the domain controller and workstation virtual machines.')
@minLength(1)
@maxLength(20)
param adminUsername string = 'BlueTeamLab'

@description('Administrator password for both the domain controller and workstation virtual machines.')
@minLength(12)
@maxLength(123)
@secure()
param adminPassword string

// Log Analytics workspace parameters
@description('Globally unique name for the Log Analytics workspace.')
param logAnalyticsWorkspaceName string

// Deploy the virtual network
module virtualNetwork 'modules/network.bicep' = {
  name: 'virtualNetwork'
  params: {
    location: location
    virtualNetworkName: virtualNetworkName
    virtualNetworkAddressSpace: virtualNetworkAddressSpace
    subnetName: subnetName
    subnetAddressRange: subnetAddressRange
    allowedSourceIPAddress: allowedSourceIPAddress
  }
}

// Deploy the domain controller
module domainController 'modules/vm.bicep' = {
  name: 'domainController'
  params: {
    location: location
    subnetId: virtualNetwork.outputs.subnetId
    vmName: domainControllerName
    vmSize: 'Standard_DS1_v2'
    vmPublisher: 'MicrosoftWindowsServer'
    vmOffer: 'WindowsServer'
    vmSku: '2019-Datacenter'
    vmVersion: 'latest'
    vmStorageAccountType: 'StandardSSD_LRS'
    adminUsername: adminUsername
    adminPassword: adminPassword
  }
}

// Use PowerShell DSC to deploy Active Directory Domain Services on the domain controller
resource domainControllerConfiguration 'Microsoft.Compute/virtualMachines/extensions@2021-11-01' = {
  name: '${domainControllerName}/Microsoft.Powershell.DSC'
  dependsOn: [
    domainController
  ]
  location: location
  properties: {
    publisher: 'Microsoft.Powershell'
    type: 'DSC'
    typeHandlerVersion: '2.77'
    autoUpgradeMinorVersion: true
    settings: {
      ModulesUrl: 'https://github.com/joshua-a-lucas/BlueTeamLab/raw/main/scripts/Deploy-DomainServices.zip'
      ConfigurationFunction: 'Deploy-DomainServices.ps1\\Deploy-DomainServices'
      Properties: {
        domainFQDN: domainFQDN
        adminCredential: {
          UserName: adminUsername
          Password: 'PrivateSettingsRef:adminPassword'
        }
      }
    }
    protectedSettings: {
      Items: {
          adminPassword: adminPassword
      }
    }
  }
}

// Update the virtual network with the domain controller as the primary DNS server
module virtualNetworkDNS 'modules/network.bicep' = {
  name: 'virtualNetworkDNS'
  dependsOn: [
    domainControllerConfiguration
  ]
  params: {
    location: location
    virtualNetworkName: virtualNetworkName
    virtualNetworkAddressSpace: virtualNetworkAddressSpace
    subnetName: subnetName
    subnetAddressRange: subnetAddressRange
    allowedSourceIPAddress: allowedSourceIPAddress
    dnsServerIPAddress: domainController.outputs.privateIpAddress
  }
}

// Deploy the workstation once the virtual network's primary DNS server has been updated to the domain controller
module workstation 'modules/vm.bicep' = {
  name: 'workstation'
  dependsOn: [
    virtualNetworkDNS
  ]
  params: {
    location: location
    subnetId: virtualNetwork.outputs.subnetId
    vmName: workstationName
    vmSize: 'Standard_DS1_v2'
    vmPublisher: 'MicrosoftWindowsDesktop'
    vmOffer: 'Windows-10'
    vmSku: 'win10-21h2-pro'
    vmVersion: 'latest'
    vmStorageAccountType: 'StandardSSD_LRS'
    adminUsername: adminUsername
    adminPassword: adminPassword
  }
}

// Use PowerShell DSC to join the workstation to the domain
resource workstationConfiguration 'Microsoft.Compute/virtualMachines/extensions@2021-11-01' = {
  name: '${workstationName}/Microsoft.Powershell.DSC'
  dependsOn: [
    workstation
  ]
  location: location
  properties: {
    publisher: 'Microsoft.Powershell'
    type: 'DSC'
    typeHandlerVersion: '2.77'
    autoUpgradeMinorVersion: true
    settings: {
      ModulesUrl: 'https://github.com/joshua-a-lucas/BlueTeamLab/raw/main/scripts/Join-Domain.zip'
      ConfigurationFunction: 'Join-Domain.ps1\\Join-Domain'
      Properties: {
        domainFQDN: domainFQDN
        computerName: workstationName
        adminCredential: {
          UserName: adminUsername
          Password: 'PrivateSettingsRef:adminPassword'
        }
      }
    }
    protectedSettings: {
      Items: {
          adminPassword: adminPassword
      }
    }
  }
}

// Deploy the Microsoft Sentinel instance
module workspace 'modules/sentinel.bicep' = {
  name: 'microsoftSentinel'
  params: {
    location: location
    logAnalyticsWorkspaceName: logAnalyticsWorkspaceName
    retentionInDays: 30
    sku: 'PerGB2018'
    dailyQuotaGb: 5
  }
}

// Create data collection rule
resource dcr 'Microsoft.Insights/dataCollectionRules@2021-04-01' = {
  name: 'DCR'
  location: location
  kind: 'Windows'
  tags: {
    createdBy: 'Sentinel'
  }
  properties: {
    dataFlows: [
      {
        destinations: [
          logAnalyticsWorkspaceName
        ]
        streams: [
          'Microsoft-SecurityEvent'
        ]
      }
    ]
    dataSources: {
      windowsEventLogs: [
        {
          name: 'windowsSecurityEventLogs'
          streams: [
            'Microsoft-SecurityEvent'
          ]
          xPathQueries: [
            'Security!*[System[(EventID=1) or (EventID=299) or (EventID=300) or (EventID=324) or (EventID=340) or (EventID=403) or (EventID=404) or (EventID=410) or (EventID=411) or (EventID=412) or (EventID=413) or (EventID=431) or (EventID=500) or (EventID=501) or (EventID=1100)]]'
            'Security!*[System[(EventID=1102) or (EventID=1107) or (EventID=1108) or (EventID=4608) or (EventID=4610) or (EventID=4611) or (EventID=4614) or (EventID=4622) or (EventID=4624) or (EventID=4625) or (EventID=4634) or (EventID=4647) or (EventID=4648) or (EventID=4649) or (EventID=4657)]]'
            'Security!*[System[(EventID=4661) or (EventID=4662) or (EventID=4663) or (EventID=4665) or (EventID=4666) or (EventID=4667) or (EventID=4688) or (EventID=4670) or (EventID=4672) or (EventID=4673) or (EventID=4674) or (EventID=4675) or (EventID=4689) or (EventID=4697) or (EventID=4700)]]'
            'Security!*[System[(EventID=4702) or (EventID=4704) or (EventID=4705) or (EventID=4716) or (EventID=4717) or (EventID=4718) or (EventID=4719) or (EventID=4720) or (EventID=4722) or (EventID=4723) or (EventID=4724) or (EventID=4725) or (EventID=4726) or (EventID=4727) or (EventID=4728)]]'
            'Security!*[System[(EventID=4729) or (EventID=4733) or (EventID=4732) or (EventID=4735) or (EventID=4737) or (EventID=4738) or (EventID=4739) or (EventID=4740) or (EventID=4742) or (EventID=4744) or (EventID=4745) or (EventID=4746) or (EventID=4750) or (EventID=4751) or (EventID=4752)]]'
            'Security!*[System[(EventID=4754) or (EventID=4755) or (EventID=4756) or (EventID=4757) or (EventID=4760) or (EventID=4761) or (EventID=4762) or (EventID=4764) or (EventID=4767) or (EventID=4768) or (EventID=4771) or (EventID=4774) or (EventID=4778) or (EventID=4779) or (EventID=4781)]]'
            'Security!*[System[(EventID=4793) or (EventID=4797) or (EventID=4798) or (EventID=4799) or (EventID=4800) or (EventID=4801) or (EventID=4802) or (EventID=4803) or (EventID=4825) or (EventID=4826) or (EventID=4870) or (EventID=4886) or (EventID=4887) or (EventID=4888) or (EventID=4893)]]'
            'Security!*[System[(EventID=4898) or (EventID=4902) or (EventID=4904) or (EventID=4905) or (EventID=4907) or (EventID=4931) or (EventID=4932) or (EventID=4933) or (EventID=4946) or (EventID=4948) or (EventID=4956) or (EventID=4985) or (EventID=5024) or (EventID=5033) or (EventID=5059)]]'
            'Security!*[System[(EventID=5136) or (EventID=5137) or (EventID=5140) or (EventID=5145) or (EventID=5632) or (EventID=6144) or (EventID=6145) or (EventID=6272) or (EventID=6273) or (EventID=6278) or (EventID=6416) or (EventID=6423) or (EventID=6424) or (EventID=8001) or (EventID=8002)]]'
            'Security!*[System[(EventID=8003) or (EventID=8004) or (EventID=8005) or (EventID=8006) or (EventID=8007) or (EventID=8222) or (EventID=26401) or (EventID=30004)]]'
            'Microsoft-Windows-AppLocker/EXE and DLL!*[System[(EventID=8001) or (EventID=8002) or (EventID=8003) or (EventID=8004)]]'
            'Microsoft-Windows-AppLocker/MSI and Script!*[System[(EventID=8005) or (EventID=8006) or (EventID=8007)]]'
            ]
        }
      ]
    }
    description: 'Data collection rule to collect common Windows security events.'
    destinations: {
      logAnalytics: [
        {
          name: logAnalyticsWorkspaceName
          workspaceResourceId: workspace.outputs.workspaceResourceId
        }
      ]
    }
  }
}

// Create a data collection rule association for the domain controller
resource domainControllerVm 'Microsoft.Compute/virtualMachines@2021-11-01' existing = {
  name: domainControllerName
}

resource domainControllerAssociation 'Microsoft.Insights/dataCollectionRuleAssociations@2021-04-01' = {
  name: '${domainControllerName}-dcra'
  dependsOn: [
    workspace
    domainControllerConfiguration
  ]
  scope: domainControllerVm
  properties: {
    dataCollectionRuleId: dcr.id
  }
}

// Create a data collection rule association for the workstation
resource workstationVm 'Microsoft.Compute/virtualMachines@2021-11-01' existing = {
  name: workstationName
}

resource workstationAssociation 'Microsoft.Insights/dataCollectionRuleAssociations@2021-04-01' = {
  name: '${workstationName}-dcra'
  dependsOn: [
    workspace
    workstationConfiguration
  ]
  scope: workstationVm
  properties: {
    dataCollectionRuleId: dcr.id
  }
}
