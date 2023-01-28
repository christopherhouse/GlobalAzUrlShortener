param cosmosAccountName string
param regions array

var locations = [for region in regions: {
  locationName: region
  failoverPriority: indexOf(regions, region)
  isZoneRedundant: false
}]

resource cosmosAccount 'Microsoft.DocumentDB/databaseAccounts@2022-08-15' = {
  name: cosmosAccountName
  location: regions[0]
  tags: {
    defaultExperience: 'Azure Table'
  }
  kind: 'GlobalDocumentDB'
  properties: {
    databaseAccountOfferType: 'Standard'
    publicNetworkAccess: 'Enabled'
    enableMultipleWriteLocations: length(regions) > 1
    enableAutomaticFailover: length(regions) > 1
    consistencyPolicy: {
      defaultConsistencyLevel: 'BoundedStaleness'
      maxIntervalInSeconds: 86400
      maxStalenessPrefix: 1000000
    }
    locations: locations
    capabilities: [
      {
        name: 'EnableTable'
      }
    ]
    backupPolicy: {
      type: 'Periodic'
      periodicModeProperties: {
        backupIntervalInMinutes: 360
        backupRetentionIntervalInHours: 24
        backupStorageRedundancy: 'Local'
      }
    }
    ipRules: [
      {
        ipAddressOrRange: '104.42.195.92'
      }
      {
        ipAddressOrRange: '40.76.54.131'
      }
      {
        ipAddressOrRange: '52.176.6.30'
      }
      {
        ipAddressOrRange: '52.169.50.45'
      }
      {
        ipAddressOrRange: '52.187.184.26'
      }
      {
        ipAddressOrRange: '0.0.0.0'
      }
    ]
  }
}

// Create a Cosmos DB table resource with the name UrlsDetails.  Set the throughput to autoscale with minimum 400 RUs and max 4000 RUs.
// Set the parent resource of the table to be the Cosmos DB account resource.

resource urlDetailsTable 'Microsoft.DocumentDB/databaseAccounts/tables@2022-08-15' = {
  name: 'UrlsDetails'
  parent: cosmosAccount
  properties: {
    resource: {
      id: 'UrlsDetails'
    }
    options: {
      throughput: 400
      autoscaleSettings: {
        maxThroughput: 4000
      }
    }
  }
}

resource clickStatsTable 'Microsoft.DocumentDB/databaseAccounts/tables@2022-08-15' = {
  name: 'ClickStats'
  parent: cosmosAccount
  properties: {
    resource: {
      id: 'ClickStats'
    }
    options: {
      throughput: 400
      autoscaleSettings: {
        maxThroughput: 4000
      }
    }
  }
}

output id string = cosmosAccount.id
output apiVersion string = cosmosAccount.apiVersion
