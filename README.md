# Infrastructure as Code in practice: Building a Blue Team lab with Azure Bicep
This template will deploy:
- Windows Server 2019 virtual machine, configured as a domain controller
- Windows 10 virtual machine, configured as a domain-joined workstation
- Microsoft Sentinel instance, with a Data Collection Rule (DCR) configured to ingest common Windows security events

Refer to the following blog post for more information: [Infrastructure as Code in practice: Building a Blue Team lab with Azure Bicep](https://joshua-lucas.com/building-a-blue-team-lab-with-azure-bicep/)

[![Deploy to Azure](https://aka.ms/deploytoazurebutton)](https://portal.azure.com/#create/Microsoft.Template/uri/https%3A%2F%2Fraw.githubusercontent.com%2FAzure%2Fazure-quickstart-templates%2Fmaster%2Fquickstarts%2Fmicrosoft.storage%2Fstorage-account-create%2Fazuredeploy.json)