# Infrastructure as Code in practice: Building a Blue Team lab with Bicep
This template will deploy:
- Virtual network, consisting of a default subnet and a network security group to restrict inbound RDP traffic to our local machine
- Windows Server 2019 virtual machine, configured as a domain controller
- Windows 10 virtual machine, configured as a domain-joined workstation
- Microsoft Sentinel instance, with a data collection rule configured to ingest common Windows security events from both virtual machines

Refer to the following blog post for more information: [Infrastructure as Code in practice: Building a Blue Team lab with Bicep](https://joshua-lucas.com/building-a-blue-team-lab-with-bicep/)

[![Deploy to Azure](https://aka.ms/deploytoazurebutton)](https://portal.azure.com/#create/Microsoft.Template/uri/https%3A%2F%2Fraw.githubusercontent.com%2Fjoshua-a-lucas%2FBlueTeamLab%2Fmain%2Fazuredeploy.json)