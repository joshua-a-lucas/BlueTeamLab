param location string
param virtualNetworkName string
param virtualNetworkAddressSpace string
param subnetName string
param subnetAddressRange string
param allowedSourceIPAddress string
param dnsServerIPAddress string = ''

// Create a network security group to restrict remote access to resources within the virtual network
resource nsg 'Microsoft.Network/networkSecurityGroups@2021-05-01' = {
  name: '${virtualNetworkName}-nsg'
  location: location
  properties: {
    securityRules: [
      {
        name: 'allow-inbound-rdp'
        properties: {
          priority: 1000
          access: 'Allow'
          direction: 'Inbound'
          destinationPortRange: '3389'
          protocol: 'Tcp'
          sourcePortRange: '*'
          sourceAddressPrefix: allowedSourceIPAddress
          destinationAddressPrefix: '*'
        }
      }
    ]
  }
}

// Deploy the virtual network and a default subnet associated with the network security group
resource vnet 'Microsoft.Network/virtualNetworks@2021-05-01' = {
  name: virtualNetworkName
  location: location
  properties: {
    addressSpace: {
      addressPrefixes: [
        virtualNetworkAddressSpace
      ]
    }
    dhcpOptions: {
      dnsServers: ((!empty(dnsServerIPAddress)) ? array(dnsServerIPAddress) : json('null'))
    }
    subnets: [
      {
        name: subnetName
        properties: {
          addressPrefix: subnetAddressRange
          networkSecurityGroup: {
            id: nsg.id
          }
        }
      }
    ]
  }
}

output subnetId string = vnet.properties.subnets[0].id
