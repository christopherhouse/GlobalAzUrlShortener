param frontDoorName string
@allowed([
  'Standard_AzureFrontDoor'
  'Premium_AzureFrontDoor'
  'Premium_AzureFrontDoor_With_WAF'
])
param frontDoorSku string
param deployWAF bool = false
param functionAppHostNames array
@allowed([
  'Prevention'
  'Detection'
])
param wafMode string = 'Prevention'
param wafManagedRulesets array = [
  {
    rulesetType: 'Microsoft_DefaultRuleSet'
    ruleSetVersion: '2.1'
    rulesetAction: 'Block'
  }
  {
    ruleSetType: 'Microsoft_BotManagerRuleSet'
    ruleSetVersion: '1.0'
  }
]

var profileName = '${frontDoorName}-profile'
var endpointName = '${frontDoorName}-endpoint'
var originName = '${frontDoorName}-origingroup'
var sku = frontDoorSku == 'Standard_AzureFrontDoor' ? 'Standard_AzureFrontDoor' : 'Premium_AzureFrontDoor'
var isPremiumSku = sku == 'Premium_AzureFrontDoor'
var hostNames = [for functionApp in functionAppHostNames: '${functionApp}-fa.azurewebsites.net']

resource wafPolicy 'Microsoft.Network/FrontDoorWebApplicationFirewallPolicies@2022-05-01' = if(deployWAF && isPremiumSku) {
  name: '${replace(frontDoorName, '-', '')}wafpolicy'
  location: 'global'
  sku: {
    name: 'Premium_AzureFrontDoor'
  }
  properties: {
    policySettings: {
      enabledState: 'Enabled'
      mode: wafMode
    }
    managedRules: {
      managedRuleSets: wafManagedRulesets
    }
  }
}

resource securityPolicy 'Microsoft.Cdn/profiles/securityPolicies@2022-11-01-preview' = if(deployWAF && isPremiumSku) {
  name: '${replace(frontDoorName, '-', '')}securitypolicy'
  parent: frontDoorProfile
  properties: {
    parameters: {
      type: 'WebApplicationFirewall'
      wafPolicy: {
        id: wafPolicy.id
      }
      associations: [
        {
          domains: [
            {
              id: frontDoorEndpoint.id
            }
          ]
          patternsToMatch: [
            '/*'
          ]
        }
      ]
    }
  }
}

resource frontDoorProfile 'Microsoft.Cdn/profiles@2022-11-01-preview' = {
  name: profileName
  location: 'global'
  sku: {
    name: sku
  }
}

resource frontDoorEndpoint 'Microsoft.Cdn/profiles/afdEndpoints@2022-11-01-preview' = {
  name: endpointName
  parent: frontDoorProfile
  location: 'global'
  properties: {
    enabledState: 'Enabled'
  }
}

resource originGroup 'Microsoft.Cdn/profiles/originGroups@2022-11-01-preview' = {
  name: originName
  parent: frontDoorProfile
  properties: {
    loadBalancingSettings: {
      sampleSize: 4
      successfulSamplesRequired: 2
    }
    healthProbeSettings: {
      probePath: '/'
      probeRequestType: 'GET'
      probeProtocol: 'Https'
      probeIntervalInSeconds: 30
    }
  }
}

resource frontDoorOrigin 'Microsoft.Cdn/profiles/originGroups/origins@2022-11-01-preview' = [for (hostName, i) in hostNames: {
  name: functionAppHostNames[i]
  parent: originGroup
  properties: {
    hostName: hostName
    httpPort: 80
    httpsPort: 443
    originHostHeader: hostName
    priority: 1
    weight: 1000
  }
}]

resource frontDoorRoute 'Microsoft.Cdn/profiles/afdEndpoints/routes@2022-11-01-preview' = {
  name: 'urlshortner'
  parent: frontDoorEndpoint
  properties: {
    originGroup: {
      id: originGroup.id
    }
    supportedProtocols: [
      'Http'
      'Https'
    ]
    patternsToMatch: [
      '/*'
    ]
    forwardingProtocol: 'HttpOnly'
    linkToDefaultDomain: 'Enabled'
    httpsRedirect: 'Enabled'
    cacheConfiguration: {
      queryStringCachingBehavior: 'IgnoreQueryString'
    }
  }
  dependsOn: [
    frontDoorOrigin
  ]
}

output frontDoorId string = frontDoorProfile.properties.frontDoorId
