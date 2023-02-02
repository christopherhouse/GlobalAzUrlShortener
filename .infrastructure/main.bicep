@description('Name used as base-template to name the resources to be deployed in Azure.')
param baseName string = 'ShortenerTools'

@description('Default URL used when key passed by the user is not found.')
param defaultRedirectUrl string = 'https://azure.com'

@description('An array of locations that the Function App will be deployed to.  Defaults to one region, East US')
param regions array = [
  'eastus'
]

@allowed([
  'Premium_AzureFrontDoor'
  'Premium_AzureFrontDoor_With_WAF'
  'Standard_AzureFrontDoor'
  'TrafficManager'])
param loadBalancerOption string

@description('The build ID that deploys this template')
param buildId string

@description('The location of the storage account that will be used to store the URL data.')
param sharedResourceRegion string = 'eastus'

var UrlsStorageAccountName = '${baseName}urlstorage'
var functionsCount = length(regions)
var appInsightsDeploymentName = '${baseName}-${sharedResourceRegion}-ai-${buildId}'
var functionAppNames = [for location in regions: '${baseName}-${location}']
var trafficManagerProfileName = '${baseName}-atm'
var frontDoorName = '${baseName}-afd'
var frontDoorDeploymentName= '${baseName}-${frontDoorName}-fd-${buildId}'
var deployFrontDoor = loadBalancerOption == 'Premium_AzureFrontDoor' || loadBalancerOption == 'Standard_AzureFrontDoor' || loadBalancerOption == 'Premium_AzureFrontDoor_With_WAF' ? true : false
var frontDoorSkuMap = [
  { optionName: 'Standared_AzureFrontDoor'
    skuName: 'Standard_AzureFrontDoor'
  }
  { optionName: 'Premium_AzureFrontDoor'
    skuName: 'Premium_AzureFrontDoor'
    skuTier: 'Premium'
  }
  { optionName: 'Premium_AzureFrontDoor_With_WAF'
    skuName: 'Premium_AzureFrontDoor'
    skuTier: 'Premium'
  }
]

var frontDoorSku = loadBalancerOption == 'TrafficManager'? 'Standard_AzureFrontDoor' : filter(frontDoorSkuMap, (sku) => sku.optionName == loadBalancerOption)[0].skName


var cosmosAccountName = '${baseName}-cdb'
var cosmosDeploymentName = '${cosmosAccountName}-${buildId}'
var trafficManagerProfileDeploymentName = '${trafficManagerProfileName}-${buildId}'

resource UrlsStorageAccount 'Microsoft.Storage/storageAccounts@2019-06-01' = {
  name: UrlsStorageAccountName
  location: sharedResourceRegion
  kind: 'StorageV2'
  sku: {
    name: 'Standard_LRS'
  }
}

module appInsights './modules/appInsights.bicep' = {
  name: appInsightsDeploymentName
  params: {
    appInsightsName: '${baseName}-ai'
    logAnalyticsWorkspaceName: '${baseName}-la'
    location: sharedResourceRegion
  }
}

module functionApps './modules/functionApp.bicep' = [for (location, i) in regions: {
  name: '${baseName}-${location}-fa-${buildId}'
  params: {
    functionAppName: functionAppNames[i]
    storageAccountName: '${baseName}fa${location}'
    appInsightsName: appInsights.outputs.name
    defaultRedirectUrl: defaultRedirectUrl
    location: location
    cosmosDbAccountName: cosmosAccountName
    cosmosDbApiVersion: cosmosDb.outputs.apiVersion
    cosmosDbResourceId: cosmosDb.outputs.id
  }
}]

module frontDoor './modules/frontDoor.bicep' = if (deployFrontDoor) {
  name: frontDoorDeploymentName
  params: {
    frontDoorName: frontDoorName
    functionAppHostNames: functionAppNames
    frontDoorSku: frontDoorSku
    functionAppResourceIds: [for i in range(0, functionsCount): functionApps[i].outputs.id]
  }
  dependsOn: [
    functionApps
  ]
}

module trafficManager './modules/trafficManager.bicep' = if(loadBalancerOption == 'TrafficManager') {
  name: trafficManagerProfileDeploymentName
  params: {
    trafficManagerProfileName: trafficManagerProfileName
    functionAppNames: functionAppNames
    functionRegions: regions
  }
  dependsOn: [
    functionApps
  ]
}

module cosmosDb './modules/cosmosDb.bicep' = {
  name: cosmosDeploymentName
  params: {
    cosmosAccountName: cosmosAccountName
    regions: regions
  }
}

output functionAppNames array = [for i in range(0, functionsCount): '${functionApps[i].name}']
